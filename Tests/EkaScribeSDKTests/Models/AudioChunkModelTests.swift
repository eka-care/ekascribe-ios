import XCTest
@testable import EkaScribeSDK

final class AudioChunkModelTests: XCTestCase {

    func testDurationMs() {
        let chunk = AudioChunk(
            chunkId: "session_0",
            sessionId: "session",
            index: 0,
            frames: [],
            startTimeMs: 1000,
            endTimeMs: 5000,
            quality: nil
        )
        XCTAssertEqual(chunk.durationMs, 4000)
    }

    func testDurationMsZero() {
        let chunk = AudioChunk(
            chunkId: "session_0",
            sessionId: "session",
            index: 0,
            frames: [],
            startTimeMs: 3000,
            endTimeMs: 3000,
            quality: nil
        )
        XCTAssertEqual(chunk.durationMs, 0)
    }

    func testChunkWithQuality() {
        let quality = AudioQuality(stoi: 0.8, pesq: 3.5, siSDR: 10.0, overallScore: 0.7)
        let chunk = AudioChunk(
            chunkId: "s_1",
            sessionId: "s",
            index: 1,
            frames: [makeFrame()],
            startTimeMs: 0,
            endTimeMs: 1000,
            quality: quality
        )
        XCTAssertEqual(chunk.quality?.overallScore, 0.7)
        XCTAssertEqual(chunk.index, 1)
    }
}
