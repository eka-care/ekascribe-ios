import Combine
import XCTest
@testable import EkaScribeSDK

final class SquimAudioAnalyserTests: XCTestCase {
    private var tempDir: URL!
    private var modelProvider: SquimModelProvider!
    private var logger: MockLogger!
    private var sut: SquimAudioAnalyser!

    override func setUp() {
        super.setUp()
        logger = MockLogger()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SquimAnalyserTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let modelPath = tempDir.appendingPathComponent("model.onnx")
        FileManager.default.createFile(atPath: modelPath.path, contents: Data("model".utf8))

        modelProvider = SquimModelProvider(modelPath: modelPath.path, logger: logger)
        modelProvider.load()
        sut = SquimAudioAnalyser(modelProvider: modelProvider, logger: logger)
    }

    override func tearDown() {
        sut = nil
        modelProvider = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Frame Accumulation

    func testSubmitFrameAccumulatesBeforeWindow() {
        // Submit frames for less than 3 seconds — no quality should be published
        let expectation = expectation(description: "No quality published")
        expectation.isInverted = true

        let cancellable = sut.qualityFlow.sink { _ in
            expectation.fulfill()
        }

        // Each frame at 32ms intervals, 512 samples, 16kHz
        // 2 seconds = ~62 frames
        for i in 0..<62 {
            let pcm = Array(repeating: Int16(5000), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            sut.submitFrame(frame)
        }

        wait(for: [expectation], timeout: 0.5)
        cancellable.cancel()
    }

    func testQualityPublishedAfterWindow() {
        let expectation = expectation(description: "Quality published")

        let cancellable = sut.qualityFlow.sink { quality in
            XCTAssertGreaterThanOrEqual(quality.overallScore, 0.0)
            XCTAssertLessThanOrEqual(quality.overallScore, 1.0)
            expectation.fulfill()
        }

        // Submit more than 3 seconds of frames: 3000ms / 32ms ≈ 94 frames
        for i in 0..<100 {
            let pcm = Array(repeating: Int16(5000), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            sut.submitFrame(frame)
        }

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
    }

    func testMultipleWindowsPublishMultipleTimes() {
        let expectation = expectation(description: "Two quality emissions")
        expectation.expectedFulfillmentCount = 2

        let cancellable = sut.qualityFlow.sink { _ in
            expectation.fulfill()
        }

        // Submit ~6.4 seconds of frames: 200 frames * 32ms = 6400ms → should trigger at 3000ms and 6000ms
        for i in 0..<200 {
            let pcm = Array(repeating: Int16(5000), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            sut.submitFrame(frame)
        }

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
    }

    func testSubmitFrameWithZeroPCM() {
        let expectation = expectation(description: "Quality published for silence")

        let cancellable = sut.qualityFlow.sink { quality in
            // Silent frames → RMS = 0 → low/zero scores
            XCTAssertEqual(quality.stoi, 0.0, accuracy: 0.001)
            XCTAssertEqual(quality.pesq, -0.5, accuracy: 0.001)
            expectation.fulfill()
        }

        for i in 0..<100 {
            let pcm = Array(repeating: Int16(0), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            sut.submitFrame(frame)
        }

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
    }

    func testReleaseStopsAccumulation() {
        // Release unloads the model provider, so subsequent frames are ignored
        sut.release()
        XCTAssertFalse(modelProvider.isLoaded)

        let expectation = expectation(description: "No quality after release")
        expectation.isInverted = true

        let cancellable = sut.qualityFlow.sink { _ in
            expectation.fulfill()
        }

        for i in 0..<200 {
            let pcm = Array(repeating: Int16(5000), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            sut.submitFrame(frame)
        }

        wait(for: [expectation], timeout: 0.5)
        cancellable.cancel()
    }

    func testSubmitFrameWhenModelNotLoaded() {
        // Create analyser with unloaded model
        let unloadedProvider = SquimModelProvider(modelPath: "/nonexistent/model.onnx", logger: logger)
        let analyser = SquimAudioAnalyser(modelProvider: unloadedProvider, logger: logger)

        let expectation = expectation(description: "No quality published")
        expectation.isInverted = true

        let cancellable = analyser.qualityFlow.sink { _ in
            expectation.fulfill()
        }

        for i in 0..<200 {
            let pcm = Array(repeating: Int16(5000), count: 512)
            let frame = AudioFrame(pcm: pcm, timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            analyser.submitFrame(frame)
        }

        wait(for: [expectation], timeout: 0.5)
        cancellable.cancel()
    }

    func testConcurrentSubmitFrameDoesNotCrash() {
        let expectation = expectation(description: "Concurrent access completes")

        let group = DispatchGroup()
        for thread in 0..<4 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<50 {
                    let pcm = Array(repeating: Int16(5000), count: 512)
                    let ts = thread * 10000 + i * 32
                    let frame = AudioFrame(pcm: pcm, timestampMs: ts, sampleRate: 16000, frameIndex: thread * 50 + i)
                    self.sut.submitFrame(frame)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testSubmitFrameEmptyPCM() {
        // Frames with empty PCM should not crash and model returns nil → logger warns
        let expectation = expectation(description: "No crash with empty PCM")
        expectation.isInverted = true

        let cancellable = sut.qualityFlow.sink { _ in
            expectation.fulfill()
        }

        for i in 0..<100 {
            let frame = AudioFrame(pcm: [], timestampMs: i * 32, sampleRate: 16000, frameIndex: i)
            sut.submitFrame(frame)
        }

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }
}
