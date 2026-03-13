import XCTest
@testable import EkaScribeSDK

final class M4aAudioEncoderTests: XCTestCase {
    private var tempDir: URL!
    private var logger: MockLogger!
    private var encoder: M4aAudioEncoder!

    override func setUp() {
        super.setUp()
        logger = MockLogger()
        encoder = M4aAudioEncoder(logger: logger)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncoderTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testEncodeCreatesOutputFile() async throws {
        let sampleRate = 16000
        // Generate 1 second of sine wave PCM
        let pcm = generateSineWave(sampleCount: sampleRate, frequency: 440, sampleRate: sampleRate)
        let frames = [AudioFrame(pcm: pcm, timestampMs: 0, sampleRate: sampleRate, frameIndex: 0)]
        let outputPath = tempDir.appendingPathComponent("test.m4a").path

        let encoded = try await encoder.encode(frames: frames, sampleRate: sampleRate, outputPath: outputPath)

        // The output file should exist (either m4a or wav fallback)
        XCTAssertTrue(FileManager.default.fileExists(atPath: encoded.filePath))
        XCTAssertGreaterThan(encoded.sizeBytes, 0)
    }

    func testEncodeReturnsCorrectDuration() async throws {
        let sampleRate = 16000
        let sampleCount = sampleRate * 2 // 2 seconds
        let pcm = generateSineWave(sampleCount: sampleCount, frequency: 440, sampleRate: sampleRate)
        let frames = [AudioFrame(pcm: pcm, timestampMs: 0, sampleRate: sampleRate, frameIndex: 0)]
        let outputPath = tempDir.appendingPathComponent("duration_test.m4a").path

        let encoded = try await encoder.encode(frames: frames, sampleRate: sampleRate, outputPath: outputPath)

        XCTAssertEqual(encoded.durationMs, 2000)
    }

    func testEncodeMultipleFrames() async throws {
        let sampleRate = 16000
        let frameSize = 512
        var frames: [AudioFrame] = []
        for i in 0..<31 { // ~31 frames ≈ 1 second at 512 samples/frame
            let pcm = generateSineWave(sampleCount: frameSize, frequency: 440, sampleRate: sampleRate)
            frames.append(AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: sampleRate, frameIndex: i))
        }

        let outputPath = tempDir.appendingPathComponent("multi_frame.m4a").path
        let encoded = try await encoder.encode(frames: frames, sampleRate: sampleRate, outputPath: outputPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: encoded.filePath))
        XCTAssertGreaterThan(encoded.sizeBytes, 0)
    }

    func testEncodeFromFileMissingFile() async {
        let outputPath = tempDir.appendingPathComponent("output.m4a").path

        do {
            _ = try await encoder.encodeFromFile(
                pcmFilePath: "/nonexistent/file.pcm",
                sampleRate: 16000,
                outputPath: outputPath
            )
            XCTFail("Should throw for missing file")
        } catch {
            XCTAssertTrue(error is ScribeException)
            if let scribeError = error as? ScribeException {
                XCTAssertEqual(scribeError.code, .encoderFailed)
            }
        }
    }

    func testEncodeFromFileEmptyFile() async {
        let emptyFile = tempDir.appendingPathComponent("empty.pcm")
        FileManager.default.createFile(atPath: emptyFile.path, contents: Data())

        let outputPath = tempDir.appendingPathComponent("output.m4a").path

        do {
            _ = try await encoder.encodeFromFile(
                pcmFilePath: emptyFile.path,
                sampleRate: 16000,
                outputPath: outputPath
            )
            XCTFail("Should throw for empty file")
        } catch {
            XCTAssertTrue(error is ScribeException)
        }
    }

    func testEncodeFromFileValid() async throws {
        let sampleRate = 16000
        let pcm = generateSineWave(sampleCount: sampleRate, frequency: 440, sampleRate: sampleRate)

        // Write PCM to file
        let pcmFile = tempDir.appendingPathComponent("raw.pcm")
        var data = Data()
        for sample in pcm {
            var le = sample.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        try data.write(to: pcmFile)

        let outputPath = tempDir.appendingPathComponent("from_file.m4a").path
        let encoded = try await encoder.encodeFromFile(
            pcmFilePath: pcmFile.path,
            sampleRate: sampleRate,
            outputPath: outputPath
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: encoded.filePath))
        XCTAssertGreaterThan(encoded.sizeBytes, 0)
        XCTAssertEqual(encoded.durationMs, 1000)
    }

    // MARK: - Helper

    private func generateSineWave(sampleCount: Int, frequency: Double, sampleRate: Int) -> [Int16] {
        (0..<sampleCount).map { i in
            let t = Double(i) / Double(sampleRate)
            return Int16(sin(2.0 * .pi * frequency * t) * 16000)
        }
    }
}
