import Combine
import Foundation

final class VadAudioChunker: AudioChunker {
    private let vadProvider: VadProvider
    private let config: ChunkConfig
    private let sessionId: String
    private let sampleRate: Int
    private let logger: Logger

    private let preferredSamples: Int
    private let desperationSamples: Int
    private let maxSamples: Int
    private let longSilenceSamples: Int
    private let shortSilenceSamples: Int
    private let overlapSamples: Int

    private var accumulatedFrames: [AudioFrame] = []
    private var accumulatedSamples = 0
    private var silenceSamples = 0
    private var chunkIndex = 0
    private var latestQuality: AudioQuality?
    private var chunkStartSampleOffset = 0

    private let activitySubject = PassthroughSubject<VoiceActivityData, Never>()
    var activityFlow: AnyPublisher<VoiceActivityData, Never> { activitySubject.eraseToAnyPublisher() }

    init(vadProvider: VadProvider, config: ChunkConfig, sessionId: String, sampleRate: Int, logger: Logger) {
        self.vadProvider = vadProvider
        self.config = config
        self.sessionId = sessionId
        self.sampleRate = sampleRate
        self.logger = logger
        self.preferredSamples = config.preferredDurationSec * sampleRate
        self.desperationSamples = config.desperationDurationSec * sampleRate
        self.maxSamples = config.maxDurationSec * sampleRate
        self.longSilenceSamples = Int(config.longSilenceSec * Double(sampleRate))
        self.shortSilenceSamples = Int(config.shortSilenceSec * Double(sampleRate))
        self.overlapSamples = Int(config.overlapDurationSec * Double(sampleRate))
    }

    func feed(_ frame: AudioFrame) -> AudioChunk? {
        let vadResult = vadProvider.detect(pcm: frame.pcm)

        activitySubject.send(
            VoiceActivityData(
                isSpeech: vadResult.isSpeech,
                amplitude: Self.calculateAmplitude(frame.pcm),
                timestampMs: frame.timestampMs
            )
        )

        accumulatedFrames.append(frame)
        accumulatedSamples += frame.pcm.count
        silenceSamples = vadResult.isSpeech ? 0 : silenceSamples + frame.pcm.count

        if shouldChunk() {
            return createChunk(isFlush: false)
        }
        return nil
    }

    func flush() -> AudioChunk? {
        guard !accumulatedFrames.isEmpty else { return nil }
        // Skip final chunk if less than 1 second of audio
        let minFlushSamples = sampleRate // 1 second
        guard accumulatedSamples >= minFlushSamples else {
            logger.info("Chunker", "Skipping final chunk: only \(accumulatedSamples) samples (\(Double(accumulatedSamples) / Double(sampleRate))s), minimum 1s required")
            accumulatedFrames = []
            accumulatedSamples = 0
            return nil
        }
        return createChunk(isFlush: true)
    }

    func setLatestQuality(_ quality: AudioQuality?) {
        latestQuality = quality
    }

    func release() {
        vadProvider.unload()
    }

    private func shouldChunk() -> Bool {
        if accumulatedSamples >= preferredSamples && silenceSamples >= longSilenceSamples { return true }
        if accumulatedSamples >= desperationSamples && silenceSamples >= shortSilenceSamples { return true }
        if accumulatedSamples >= maxSamples {
            logger.warn("Chunker", "Max chunk duration reached, force cutting")
            return true
        }
        return false
    }

    private func createChunk(isFlush: Bool) -> AudioChunk {
        let startMs = Int(Double(chunkStartSampleOffset) / Double(sampleRate) * 1000)
        let endMs = Int(Double(chunkStartSampleOffset + accumulatedSamples) / Double(sampleRate) * 1000)

        let chunk = AudioChunk(
            chunkId: IdGenerator.chunkId(sessionId: sessionId, index: chunkIndex),
            sessionId: sessionId,
            index: chunkIndex,
            frames: accumulatedFrames,
            startTimeMs: startMs,
            endTimeMs: endMs,
            quality: latestQuality
        )

        if !isFlush && overlapSamples > 0 {
            let overlapFrames = keepOverlapFrames()
            let overlapCount = overlapFrames.reduce(0) { $0 + $1.pcm.count }
            chunkStartSampleOffset += (accumulatedSamples - overlapCount)
            accumulatedFrames = overlapFrames
            accumulatedSamples = overlapCount
        } else {
            chunkStartSampleOffset += accumulatedSamples
            accumulatedFrames = []
            accumulatedSamples = 0
        }

        silenceSamples = 0
        chunkIndex += 1
        return chunk
    }

    static func calculateAmplitude(_ pcm: [Int16]) -> Float {
        let maxVal = pcm.map { abs(Int32($0)) }.max() ?? 0
        return Float(maxVal) / 32767.0
    }

    private func keepOverlapFrames() -> [AudioFrame] {
        var kept: [AudioFrame] = []
        var sampleCount = 0

        for frame in accumulatedFrames.reversed() {
            if sampleCount + frame.pcm.count > overlapSamples { break }
            kept.insert(frame, at: 0)
            sampleCount += frame.pcm.count
        }
        return kept
    }
}
