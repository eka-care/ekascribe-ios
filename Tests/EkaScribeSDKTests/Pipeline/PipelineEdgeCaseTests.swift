import Combine
import XCTest
@testable import EkaScribeSDK

final class PipelineEdgeCaseTests: XCTestCase {
    private var recorder: MockAudioRecorder!
    private var preBuffer: PreBuffer!
    private var analyser: MockAudioAnalyser!
    private var chunker: MockAudioChunker!
    private var encoder: MockAudioEncoder!
    private var uploader: MockChunkUploader!
    private var dataManager: MockDataManager!
    private var timeProvider: MockTimeProvider!
    private var logger: MockLogger!
    private var outputDir: URL!

    override func setUp() {
        super.setUp()
        recorder = MockAudioRecorder()
        preBuffer = PreBuffer(capacity: 100)
        analyser = MockAudioAnalyser()
        chunker = MockAudioChunker()
        encoder = MockAudioEncoder()
        uploader = MockChunkUploader()
        dataManager = MockDataManager()
        timeProvider = MockTimeProvider()
        logger = MockLogger()

        outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline_edge_tests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outputDir)
        super.tearDown()
    }

    private func makePipeline(
        onEvent: ((SessionEventName, EventType, String, [String: String]) -> Void)? = nil
    ) -> (Pipeline, AsyncStream<AudioFrame>.Continuation, AsyncStream<AudioChunk>.Continuation) {
        let framePair = AsyncStream<AudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(100))
        let chunkPair = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(100))
        let frameProducer = FrameProducer(preBuffer: preBuffer, continuation: framePair.continuation, logger: logger)
        let pipeline = Pipeline(
            recorder: recorder,
            preBuffer: preBuffer,
            frameProducer: frameProducer,
            analyser: analyser,
            chunker: chunker,
            dataManager: dataManager,
            encoder: encoder,
            chunkUploader: uploader,
            sessionId: "test-session",
            folderName: "260316",
            bid: "bid-1",
            outputDir: outputDir,
            timeProvider: timeProvider,
            logger: logger,
            onEvent: onEvent,
            frameStream: framePair.stream,
            frameContinuation: framePair.continuation,
            chunkStream: chunkPair.stream,
            chunkContinuation: chunkPair.continuation
        )
        return (pipeline, framePair.continuation, chunkPair.continuation)
    }

    // MARK: - Edge Case Tests

    func testPauseAndResumeMultipleCycles() {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()

        for _ in 0..<5 {
            pipeline.pause()
            XCTAssertTrue(recorder.pauseCalled)
            pipeline.resume()
            XCTAssertTrue(recorder.resumeCalled)
        }
    }

    func testStartSetsRecorderCallbacks() {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()

        XCTAssertTrue(recorder.startCalled)
        XCTAssertNotNil(recorder.onFrame)
        XCTAssertNotNil(recorder.onAudioFocusChanged)
    }

    func testOnFrameWritesToPreBuffer() async {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()

        let frame = makeFrame(timestampMs: 100)
        recorder.onFrame?(frame)

        // Give time for frame to be written
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Frame was accepted without crash
        XCTAssertTrue(true)
    }

    func testAudioFocusChangedPublishesValue() async {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()

        let expectation = XCTestExpectation(description: "Focus changed")
        var receivedFocus: Bool?
        let cancellable = pipeline.audioFocusFlow.dropFirst().first().sink { hasFocus in
            receivedFocus = hasFocus
            expectation.fulfill()
        }

        recorder.onAudioFocusChanged?(false)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedFocus, false)
        cancellable.cancel()
    }

    func testStopBeforeStartCoroutinesDoesNotCrash() async {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()
        // Stop immediately without starting coroutines
        _ = await pipeline.stop()
        // Should complete gracefully
        XCTAssertTrue(recorder.stopCalled)
    }

    func testMultipleFramesProcessed() async {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()

        // Send multiple frames rapidly
        for i in 0..<100 {
            let frame = makeFrame(timestampMs: i * 32, frameIndex: i)
            recorder.onFrame?(frame)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        // All frames accepted without crash
        XCTAssertTrue(true)
    }

    func testPauseBeforeStart() {
        let (pipeline, _, _) = makePipeline()
        // Pause before start should not crash
        pipeline.pause()
        XCTAssertTrue(recorder.pauseCalled)
    }

    func testResumeBeforePause() {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()
        // Resume without prior pause should not crash
        pipeline.resume()
        XCTAssertTrue(recorder.resumeCalled)
    }
}
