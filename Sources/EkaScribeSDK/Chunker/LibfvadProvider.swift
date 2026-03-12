import Foundation
import libfvad

final class LibfvadProvider: VadProvider {
    private let sampleRate: Int
    private let frameSize: Int
    private let logger: Logger
    private var detector: VoiceActivityDetector?

    init(sampleRate: Int, frameSize: Int, logger: Logger) {
        self.sampleRate = sampleRate
        self.frameSize = frameSize
        self.logger = logger
    }

    func load() {
        let vad = VoiceActivityDetector()
        do {
            try vad.setMode(mode: .lowBitrate)
            try vad.setSampleRate(sampleRate: sampleRate)
            detector = vad
            logger.debug("VAD", "Loaded libfvad at \(sampleRate)Hz frame=\(frameSize)")
        } catch {
            logger.error("VAD", "Failed to configure libfvad", error)
            detector = nil
        }
    }

    func detect(pcm: [Int16]) -> VadResult {
        guard let detector else {
            logger.error("VAD", "Detector not initialized")
            return VadResult(isSpeech: false, confidence: 0)
        }

        // libfvad requires 10ms, 20ms, or 30ms frames.
        // At 16kHz: 160, 320, or 480 samples. Process in 20ms sub-frames.
        let subFrameSize = sampleRate / 50 // 320 samples at 16kHz (20ms)
        guard subFrameSize > 0 else {
            return VadResult(isSpeech: false, confidence: 0)
        }

        var speechFrames = 0
        var totalSubFrames = 0
        var offset = 0

        while offset + subFrameSize <= pcm.count {
            do {
                let result = try pcm.withUnsafeBufferPointer { ptr in
                    try detector.process(frame: ptr.baseAddress! + offset, length: subFrameSize)
                }
                if result == .activeVoice {
                    speechFrames += 1
                }
                totalSubFrames += 1
            } catch {
                logger.error("VAD", "Failed to process sub-frame", error)
            }
            offset += subFrameSize
        }

        let isSpeech = totalSubFrames > 0 && speechFrames > totalSubFrames / 2
        let confidence = totalSubFrames > 0 ? Float(speechFrames) / Float(totalSubFrames) : 0
        logger.error("VAD", "isSpeech: \(isSpeech), confidence: \(confidence)")
        return VadResult(isSpeech: isSpeech, confidence: confidence)
    }

    func unload() {
        detector = nil
    }
}
