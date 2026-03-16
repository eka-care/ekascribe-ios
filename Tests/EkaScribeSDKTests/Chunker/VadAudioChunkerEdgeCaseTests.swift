import Combine
import XCTest
@testable import EkaScribeSDK

final class VadAudioChunkerEdgeCaseTests: XCTestCase {
    private var vadProvider: MockVadProvider!
    private var logger: MockLogger!
    private var config: ChunkConfig!

    override func setUp() {
        super.setUp()
        vadProvider = MockVadProvider()
        logger = MockLogger()
        config = ChunkConfig()
    }

    private func makeChunker(config: ChunkConfig? = nil) -> VadAudioChunker {
        VadAudioChunker(
            vadProvider: vadProvider,
            config: config ?? self.config,
            sessionId: "test-session",
            sampleRate: 16000,
            logger: logger
        )
    }

    private func feedFrames(
        _ chunker: VadAudioChunker,
        count: Int,
        isSpeech: Bool,
        sampleCount: Int = 512,
        sampleRate: Int = 16000
    ) -> AudioChunk? {
        vadProvider.isSpeech = isSpeech
        var lastResult: AudioChunk?
        for i in 0..<count {
            let pcm = Array(repeating: isSpeech ? Int16(5000) : Int16(0), count: sampleCount)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: sampleRate, frameIndex: i)
            if let chunk = chunker.feed(frame) {
                lastResult = chunk
            }
        }
        return lastResult
    }

    // MARK: - Edge Case Tests

    func testFlushWithExactlyOneSecond() {
        let chunker = makeChunker()
        vadProvider.isSpeech = true

        // Feed exactly 1 second of frames: 16000 samples / 512 = ~31.25 frames
        let framesForOneSecond = 32 // slightly over 1 second
        for i in 0..<framesForOneSecond {
            let pcm = Array(repeating: Int16(5000), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            _ = chunker.feed(frame)
        }

        let flushed = chunker.flush()
        XCTAssertNotNil(flushed, "Flush should return chunk for >= 1 second of audio")
    }

    func testFlushWithJustBelowOneSecond() {
        let chunker = makeChunker()
        vadProvider.isSpeech = true

        // Feed less than 1 second: ~15 frames = 15 * 512 / 16000 = 0.48s
        let framesBelow = 15
        for i in 0..<framesBelow {
            let pcm = Array(repeating: Int16(5000), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            _ = chunker.feed(frame)
        }

        let flushed = chunker.flush()
        XCTAssertNil(flushed, "Flush should return nil for < 1 second of audio")
    }

    func testMaxDurationCutMidSpeech() {
        let chunker = makeChunker()
        vadProvider.isSpeech = true

        // Feed 26 seconds of speech (above max of 25s): 26 * 16000 / 512 = 812.5 frames
        let framesFor26Seconds = 813
        var chunkCreated = false
        for i in 0..<framesFor26Seconds {
            let pcm = Array(repeating: Int16(8000), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            if let _ = chunker.feed(frame) {
                chunkCreated = true
            }
        }

        XCTAssertTrue(chunkCreated, "Should force-cut at max duration even during speech")
    }

    func testChunkTimestampsFromFrames() {
        let chunker = makeChunker()
        vadProvider.isSpeech = true

        // Feed enough for preferred duration + silence
        // Preferred = 10s → 10 * 16000 / 512 = 312.5 → 313 frames
        for i in 0..<313 {
            let pcm = Array(repeating: Int16(5000), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            _ = chunker.feed(frame)
        }

        // Now add silence to trigger chunk
        vadProvider.isSpeech = false
        let silenceFrames = 20 // ~0.64s silence
        var createdChunk: AudioChunk?
        for i in 0..<silenceFrames {
            let pcm = Array(repeating: Int16(0), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: (313 + i) * 32, sampleRate: 16000, frameIndex: 313 + i)
            if let chunk = chunker.feed(frame) {
                createdChunk = chunk
            }
        }

        if let chunk = createdChunk {
            XCTAssertEqual(chunk.startTimeMs, 0)
            XCTAssertTrue(chunk.endTimeMs > 0)
            XCTAssertEqual(chunk.durationMs, chunk.endTimeMs - chunk.startTimeMs)
        }
    }

    func testFeedWithAlternatingSpeechSilence() {
        let chunker = makeChunker()

        // Alternate speech and silence in small bursts (below preferred duration)
        for cycle in 0..<5 {
            vadProvider.isSpeech = true
            for i in 0..<30 { // ~0.96s speech
                let pcm = Array(repeating: Int16(5000), count: 512)
                let idx = cycle * 60 + i
                let frame = AudioFrame(pcm: pcm, timestampMs: idx * 32, sampleRate: 16000, frameIndex: idx)
                _ = chunker.feed(frame)
            }
            vadProvider.isSpeech = false
            for i in 30..<60 { // ~0.96s silence
                let pcm = Array(repeating: Int16(0), count: 512)
                let idx = cycle * 60 + i
                let frame = AudioFrame(pcm: pcm, timestampMs: idx * 32, sampleRate: 16000, frameIndex: idx)
                _ = chunker.feed(frame)
            }
        }

        // Total: 5 * 1.92s = 9.6s — below preferred threshold (10s)
        // No chunk should be created yet
        let flushed = chunker.flush()
        // 9.6s > 1s minimum → flush should produce a chunk
        XCTAssertNotNil(flushed)
    }

    func testChunkIndexStartsAtZero() {
        let chunker = makeChunker()
        vadProvider.isSpeech = true

        // Feed enough for max duration to force a chunk
        let framesFor26Seconds = 813
        var firstChunk: AudioChunk?
        for i in 0..<framesFor26Seconds {
            let pcm = Array(repeating: Int16(8000), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            if let chunk = chunker.feed(frame) {
                if firstChunk == nil { firstChunk = chunk }
            }
        }

        XCTAssertNotNil(firstChunk)
        XCTAssertEqual(firstChunk?.index, 0)
    }
}
