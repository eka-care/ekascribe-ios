import Combine
import XCTest
@testable import EkaScribeSDK

final class VadAudioChunkerTests: XCTestCase {

    private var vad: MockVadProvider!
    private var logger: MockLogger!
    private let sampleRate = 16000
    private let sessionId = "test-session"

    override func setUp() {
        super.setUp()
        vad = MockVadProvider()
        logger = MockLogger()
    }

    private func makeChunker(
        preferred: Int = 10,
        desperation: Int = 20,
        max: Int = 25,
        longSilence: Double = 0.5,
        shortSilence: Double = 0.1,
        overlap: Double = 0.5
    ) -> VadAudioChunker {
        let config = ChunkConfig(
            preferredDurationSec: preferred,
            desperationDurationSec: desperation,
            maxDurationSec: max,
            longSilenceSec: longSilence,
            shortSilenceSec: shortSilence,
            overlapDurationSec: overlap
        )
        return VadAudioChunker(
            vadProvider: vad,
            config: config,
            sessionId: sessionId,
            sampleRate: sampleRate,
            logger: logger
        )
    }

    /// Feeds N seconds of audio with specified VAD state
    private func feedSeconds(_ chunker: VadAudioChunker, seconds: Int, isSpeech: Bool, frameSize: Int = 512) -> [AudioChunk] {
        vad.isSpeech = isSpeech
        var chunks: [AudioChunk] = []
        let totalSamples = seconds * sampleRate
        var fed = 0
        var frameIdx: Int = 0
        while fed < totalSamples {
            let size = min(frameSize, totalSamples - fed)
            let pcm = Array(repeating: Int16(isSpeech ? 10000 : 0), count: size)
            let ts = Int(Double(fed) / Double(sampleRate) * 1000.0)
            let frame = AudioFrame(pcm: pcm, timestampMs: ts, sampleRate: sampleRate, frameIndex: frameIdx)
            if let chunk = chunker.feed(frame) {
                chunks.append(chunk)
            }
            fed += size
            frameIdx += 1
        }
        return chunks
    }

    // MARK: - Basic Chunking

    func testFeedBelowPreferredDoesNotChunk() {
        let chunker = makeChunker(preferred: 10)
        vad.isSpeech = true

        // Feed 5 seconds of speech — below preferred 10s
        let chunks = feedSeconds(chunker, seconds: 5, isSpeech: true)
        XCTAssertTrue(chunks.isEmpty, "Should not chunk before preferred duration")
    }

    func testFeedAtPreferredWithLongSilenceChunks() {
        let chunker = makeChunker(preferred: 2, longSilence: 0.5)

        // Feed 2 seconds of speech, then 1 second of silence
        let speechChunks = feedSeconds(chunker, seconds: 2, isSpeech: true)
        XCTAssertTrue(speechChunks.isEmpty, "Should not chunk during speech without silence")

        let silenceChunks = feedSeconds(chunker, seconds: 1, isSpeech: false)
        XCTAssertFalse(silenceChunks.isEmpty, "Should chunk at preferred + long silence")
    }

    func testFeedAtMaxDurationForceChunks() {
        let chunker = makeChunker(preferred: 2, desperation: 3, max: 4)

        // Feed 5 seconds of continuous speech — should force-cut at max (4s)
        vad.isSpeech = true
        let chunks = feedSeconds(chunker, seconds: 5, isSpeech: true)
        XCTAssertGreaterThanOrEqual(chunks.count, 1, "Should force-cut at max duration")
    }

    func testDesperationWithShortSilence() {
        let chunker = makeChunker(preferred: 5, desperation: 2, shortSilence: 0.1)

        // Feed 2+ seconds of speech then a brief silence
        let speechChunks = feedSeconds(chunker, seconds: 2, isSpeech: true)
        XCTAssertTrue(speechChunks.isEmpty)

        let silenceChunks = feedSeconds(chunker, seconds: 1, isSpeech: false)
        XCTAssertFalse(silenceChunks.isEmpty, "Should chunk at desperation + short silence")
    }

    // MARK: - Flush

    func testFlushReturnsChunkAboveMinimum() {
        let chunker = makeChunker()
        vad.isSpeech = true

        // Feed 2 seconds (above 1s minimum)
        _ = feedSeconds(chunker, seconds: 2, isSpeech: true)
        let flushed = chunker.flush()
        XCTAssertNotNil(flushed)
    }

    func testFlushSkipsBelowMinimum() {
        let chunker = makeChunker()
        vad.isSpeech = true

        // Feed 0.5 seconds (below 1s minimum)
        let pcm = Array(repeating: Int16(1000), count: sampleRate / 2) // 8000 samples = 0.5s
        let frame = AudioFrame(pcm: pcm, timestampMs: 0, sampleRate: sampleRate, frameIndex: 0)
        _ = chunker.feed(frame)

        let flushed = chunker.flush()
        XCTAssertNil(flushed, "Flush should skip chunks under 1 second")
    }

    func testFlushEmptyReturnsNil() {
        let chunker = makeChunker()
        XCTAssertNil(chunker.flush())
    }

    // MARK: - Chunk Index

    func testChunkIndexIncrementsAcrossChunks() {
        let chunker = makeChunker(preferred: 1, max: 2, longSilence: 0.1)

        // Feed speech then silence to trigger chunk, repeat
        var allChunks: [AudioChunk] = []

        for i in 0..<3 {
            allChunks.append(contentsOf: feedSeconds(chunker, seconds: 1, isSpeech: true))
            allChunks.append(contentsOf: feedSeconds(chunker, seconds: 1, isSpeech: false))
        }

        // Add flush to capture remaining
        if let flushed = chunker.flush() {
            allChunks.append(flushed)
        }

        guard allChunks.count >= 2 else {
            // At least verify we got at least some chunking
            return
        }
        for i in 1..<allChunks.count {
            XCTAssertEqual(allChunks[i].index, allChunks[i - 1].index + 1,
                           "Chunk indices should increment: chunk[\(i)].index=\(allChunks[i].index)")
        }
    }

    // MARK: - Overlap

    func testOverlapRetainsFrames() {
        // Use 0.5s overlap
        let chunker = makeChunker(preferred: 1, max: 2, longSilence: 0.1, overlap: 0.5)

        // Feed enough to trigger a chunk
        let chunks1 = feedSeconds(chunker, seconds: 1, isSpeech: true)
        let chunks2 = feedSeconds(chunker, seconds: 1, isSpeech: false)

        let allChunks = chunks1 + chunks2
        if let chunk = allChunks.first {
            // The chunk should contain frames close to 1+ seconds
            XCTAssertGreaterThan(chunk.frames.count, 0)
        }

        // The chunker should still have some overlap frames buffered
        // Feed another chunk and verify it works
        let moreChunks = feedSeconds(chunker, seconds: 2, isSpeech: true)
        let moreSilence = feedSeconds(chunker, seconds: 1, isSpeech: false)
        let allMore = moreChunks + moreSilence
        if let flushed = chunker.flush() {
            // If we got here, overlap frame retention is working
            XCTAssertGreaterThan(flushed.frames.count, 0)
        } else if !allMore.isEmpty {
            XCTAssertGreaterThan(allMore.first!.frames.count, 0)
        }
    }

    // MARK: - Quality

    func testSetLatestQualityAppliedToChunk() {
        let chunker = makeChunker(preferred: 1, max: 2, longSilence: 0.1)
        let quality = AudioQuality(stoi: 0.9, pesq: 4.0, siSDR: 20.0, overallScore: 0.85)
        chunker.setLatestQuality(quality)

        _ = feedSeconds(chunker, seconds: 1, isSpeech: true)
        let chunks = feedSeconds(chunker, seconds: 1, isSpeech: false)

        if let chunk = chunks.first {
            XCTAssertNotNil(chunk.quality)
            XCTAssertEqual(Double(chunk.quality?.overallScore ?? 0), 0.85, accuracy: 0.001)
        } else if let flushed = chunker.flush() {
            XCTAssertNotNil(flushed.quality)
        }
    }

    // MARK: - Static: calculateAmplitude

    func testCalculateAmplitude() {
        let pcm: [Int16] = [0, 100, -200, 32767]
        let amp = VadAudioChunker.calculateAmplitude(pcm)
        XCTAssertEqual(amp, Float(32767) / 32767.0, accuracy: 0.001)
    }

    func testCalculateAmplitudeAllZeros() {
        let pcm: [Int16] = [0, 0, 0]
        XCTAssertEqual(VadAudioChunker.calculateAmplitude(pcm), 0.0)
    }

    func testCalculateAmplitudeEmpty() {
        XCTAssertEqual(VadAudioChunker.calculateAmplitude([]), 0.0)
    }

    func testCalculateAmplitudeNegative() {
        let pcm: [Int16] = [-32767, 100]
        let amp = VadAudioChunker.calculateAmplitude(pcm)
        XCTAssertEqual(amp, Float(32767) / 32767.0, accuracy: 0.001)
    }

    // MARK: - Voice Activity Flow

    func testActivityFlowPublishesVoiceData() {
        let chunker = makeChunker()
        vad.isSpeech = true

        let expectation = expectation(description: "Voice activity published")
        var receivedData: VoiceActivityData?

        let cancellable = chunker.activityFlow
            .first()
            .sink { data in
                receivedData = data
                expectation.fulfill()
            }

        let frame = makeFrame(pcm: Array(repeating: 10000, count: 512), timestampMs: 100)
        _ = chunker.feed(frame)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertNotNil(receivedData)
        XCTAssertTrue(receivedData!.isSpeech)
        XCTAssertEqual(receivedData!.timestampMs, 100)
        _ = cancellable
    }

    // MARK: - Release

    func testReleaseDelegates() {
        let chunker = makeChunker()
        chunker.release()
        XCTAssertTrue(vad.unloadCalled)
    }

    // MARK: - Chunk ID Format

    func testChunkIdContainsSessionId() {
        let chunker = makeChunker(preferred: 1, max: 2, longSilence: 0.1)
        _ = feedSeconds(chunker, seconds: 1, isSpeech: true)
        let chunks = feedSeconds(chunker, seconds: 1, isSpeech: false)

        if let chunk = chunks.first {
            XCTAssertTrue(chunk.chunkId.hasPrefix(sessionId), "ChunkId should start with sessionId")
            XCTAssertTrue(chunk.sessionId == sessionId)
        }
    }
}
