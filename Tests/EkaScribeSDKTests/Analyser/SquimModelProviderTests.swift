import XCTest
@testable import EkaScribeSDK

final class SquimModelProviderTests: XCTestCase {
    private var tempDir: URL!
    private var logger: MockLogger!

    override func setUp() {
        super.setUp()
        logger = MockLogger()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SquimTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func createModelFile() -> String {
        let path = tempDir.appendingPathComponent("model.onnx")
        FileManager.default.createFile(atPath: path.path, contents: Data("model".utf8))
        return path.path
    }

    func testLoadWithMissingFile() {
        let provider = SquimModelProvider(modelPath: "/nonexistent/model.onnx", logger: logger)
        provider.load()
        XCTAssertFalse(provider.isLoaded)
    }

    func testLoadWithValidFile() {
        let modelPath = createModelFile()
        let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
        provider.load()
        XCTAssertTrue(provider.isLoaded)
    }

    func testUnload() {
        let modelPath = createModelFile()
        let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
        provider.load()
        XCTAssertTrue(provider.isLoaded)

        provider.unload()
        XCTAssertFalse(provider.isLoaded)
    }

    func testAnalyzeWhenNotLoaded() {
        let provider = SquimModelProvider(modelPath: "/missing.onnx", logger: logger)
        let frames = [makeFrame(pcm: [100, 200, 300])]
        let result = provider.analyze(frames: frames)
        XCTAssertNil(result)
    }

    func testAnalyzeEmptyFrames() {
        let modelPath = createModelFile()
        let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
        provider.load()
        let result = provider.analyze(frames: [])
        XCTAssertNil(result)
    }

    func testAnalyzeEmptyPCM() {
        let modelPath = createModelFile()
        let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
        provider.load()
        let result = provider.analyze(frames: [makeFrame(pcm: [])])
        XCTAssertNil(result)
    }

    func testAnalyzeWithSilence() {
        let modelPath = createModelFile()
        let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
        provider.load()

        let silence = Array(repeating: Int16(0), count: 16000) // 1 second silence
        let frames = [makeFrame(pcm: silence)]
        let result = provider.analyze(frames: frames)

        XCTAssertNotNil(result)
        // RMS of silence = 0, so all metrics should be at minimum
        XCTAssertEqual(result!.stoi, 0.0, accuracy: 0.001)
        XCTAssertEqual(result!.pesq, -0.5, accuracy: 0.001)
        XCTAssertEqual(result!.siSDR, -20.0, accuracy: 0.001)
    }

    func testAnalyzeWithLoudSignal() {
        let modelPath = createModelFile()
        let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
        provider.load()

        let loud = Array(repeating: Int16(20000), count: 16000)
        let result = provider.analyze(frames: [makeFrame(pcm: loud)])

        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.stoi, 0.0)
        XCTAssertGreaterThan(result!.pesq, -0.5)
        XCTAssertGreaterThan(result!.overallScore, 0.0)
    }

    func testStoiRange() {
        let modelPath = createModelFile()
        let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
        provider.load()

        let pcm = Array(repeating: Int16(30000), count: 16000)
        let result = provider.analyze(frames: [makeFrame(pcm: pcm)])!

        XCTAssertGreaterThanOrEqual(result.stoi, 0.0)
        XCTAssertLessThanOrEqual(result.stoi, 1.0)
    }

    func testPesqRange() {
        let modelPath = createModelFile()
        let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
        provider.load()

        let pcm = Array(repeating: Int16(10000), count: 16000)
        let result = provider.analyze(frames: [makeFrame(pcm: pcm)])!

        XCTAssertGreaterThanOrEqual(result.pesq, -0.5)
        XCTAssertLessThanOrEqual(result.pesq, 4.5)
    }

    func testSiSDRRange() {
        let modelPath = createModelFile()
        let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
        provider.load()

        let pcm = Array(repeating: Int16(5000), count: 16000)
        let result = provider.analyze(frames: [makeFrame(pcm: pcm)])!

        XCTAssertGreaterThanOrEqual(result.siSDR, -20.0)
        XCTAssertLessThanOrEqual(result.siSDR, 30.0)
    }

    func testOverallScoreRange() {
        let modelPath = createModelFile()
        let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
        provider.load()

        let pcm = Array(repeating: Int16(15000), count: 16000)
        let result = provider.analyze(frames: [makeFrame(pcm: pcm)])!

        XCTAssertGreaterThanOrEqual(result.overallScore, 0.0)
        XCTAssertLessThanOrEqual(result.overallScore, 1.0)
    }
}
