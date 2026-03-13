import XCTest
@testable import EkaScribeSDK

final class EncodedChunkTests: XCTestCase {

    // MARK: - File Extension

    func testWavExtension() {
        XCTAssertEqual(EncodedChunk.AudioFormat.wav.fileExtension, "wav")
    }

    func testM4aExtension() {
        XCTAssertEqual(EncodedChunk.AudioFormat.m4a.fileExtension, "m4a")
    }

    // MARK: - MIME Type

    func testWavMimeType() {
        XCTAssertEqual(EncodedChunk.AudioFormat.wav.mimeType, "audio/wav")
    }

    func testM4aMimeType() {
        XCTAssertEqual(EncodedChunk.AudioFormat.m4a.mimeType, "audio/mp4")
    }

    // MARK: - from(filePath:)

    func testFromFilePathWav() {
        let format = EncodedChunk.AudioFormat.from(filePath: "/tmp/audio.wav")
        XCTAssertEqual(format.fileExtension, "wav")
    }

    func testFromFilePathWavUppercase() {
        let format = EncodedChunk.AudioFormat.from(filePath: "/tmp/audio.WAV")
        XCTAssertEqual(format.fileExtension, "wav")
    }

    func testFromFilePathWavUnderscore() {
        let format = EncodedChunk.AudioFormat.from(filePath: "/tmp/audio.wav_")
        XCTAssertEqual(format.fileExtension, "wav")
    }

    func testFromFilePathM4a() {
        let format = EncodedChunk.AudioFormat.from(filePath: "/tmp/audio.m4a")
        XCTAssertEqual(format.fileExtension, "m4a")
    }

    func testFromFilePathUnknown() {
        let format = EncodedChunk.AudioFormat.from(filePath: "/tmp/audio.mp3")
        XCTAssertEqual(format.fileExtension, "m4a") // defaults to m4a
    }

    // MARK: - EncodedChunk Properties

    func testEncodedChunkProperties() {
        let chunk = EncodedChunk(filePath: "/tmp/test.m4a", format: .m4a, sizeBytes: 1024, durationMs: 5000)
        XCTAssertEqual(chunk.filePath, "/tmp/test.m4a")
        XCTAssertEqual(chunk.sizeBytes, 1024)
        XCTAssertEqual(chunk.durationMs, 5000)
    }
}
