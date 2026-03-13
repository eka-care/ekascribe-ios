import Combine
import XCTest
@testable import EkaScribeSDK

final class PipelineTests: XCTestCase {
    private var recorder: MockAudioRecorder!
    private var preBuffer: PreBuffer!
    private var analyser: MockAudioAnalyser!
    private var chunker: MockAudioChunker!
    private var dataManager: MockDataManager!
    private var encoder: MockAudioEncoder!
    private var uploader: MockChunkUploader!
    private var timeProvider: MockTimeProvider!
    private var logger: MockLogger!
    private var outputDir: URL!

    override func setUp() {
        super.setUp()
        recorder = MockAudioRecorder()
        preBuffer = PreBuffer(capacity: 100)
        analyser = MockAudioAnalyser()
        chunker = MockAudioChunker()
        dataManager = MockDataManager()
        encoder = MockAudioEncoder()
        uploader = MockChunkUploader()
        timeProvider = MockTimeProvider()
        logger = MockLogger()
        outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PipelineTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outputDir)
        super.tearDown()
    }

    private func makePipeline(
        sessionId: String = "test-session",
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
            sessionId: sessionId,
            folderName: "240101",
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

    // MARK: - start() tests

    func testStartSetsRecorderCallbacksAndStarts() {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()

        XCTAssertTrue(recorder.startCalled)
        XCTAssertNotNil(recorder.onFrame)
        XCTAssertNotNil(recorder.onAudioFocusChanged)
    }

    func testStartCoroutinesCreatesRawPcmFile() {
        let (pipeline, _, _) = makePipeline()
        pipeline.startCoroutines()

        let pcmPath = outputDir.appendingPathComponent("test-session_raw.pcm").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: pcmPath))
    }

    func testOnFrameWritesToPreBuffer() {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()

        let frame = makeFrame(timestampMs: 100)
        recorder.onFrame?(frame)

        let drained = preBuffer.drain()
        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained[0].timestampMs, 100)
    }

    func testAudioFocusChangedPublishesValue() {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()

        let expectation = expectation(description: "focus lost")
        var receivedValue: Bool?
        let cancellable = pipeline.audioFocusFlow
            .dropFirst() // skip initial true
            .sink { hasFocus in
                receivedValue = hasFocus
                expectation.fulfill()
            }

        recorder.onAudioFocusChanged?(false)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValue, false)
        cancellable.cancel()
    }

    // MARK: - Chunking task tests

    func testChunkingTaskSubmitsFrameToAnalyser() async {
        let (pipeline, frameContinuation, _) = makePipeline()
        pipeline.startCoroutines()

        frameContinuation.yield(makeFrame(timestampMs: 1))
        frameContinuation.finish()

        // Wait for chunking task to process
        let result = await pipeline.stop()
        _ = result // don't care about result here

        XCTAssertFalse(analyser.submittedFrames.isEmpty)
    }

    func testChunkingTaskWritesPcmToFile() async {
        let (pipeline, frameContinuation, _) = makePipeline()
        pipeline.startCoroutines()

        let frame = makeFrame(pcm: [1000, 2000, 3000], timestampMs: 1, sampleRate: 16000)
        frameContinuation.yield(frame)
        frameContinuation.finish()

        _ = await pipeline.stop()

        // The raw PCM file should have been written to then cleaned up during generateFullAudio.
        // Check that the encoder's encodeFromFile was called (which means there was data).
        // Since MockAudioEncoder creates a dummy file, the full audio result should not be nil.
        // We verify the encoder was called by checking the output file exists.
        let fullAudioPath = outputDir.appendingPathComponent("test-session_full_audio.m4a").path
        // The file gets renamed to .m4a_ by generateFullAudio
        let renamedPath = fullAudioPath + "_"
        // One of these should exist if encoding succeeded
        let exists = FileManager.default.fileExists(atPath: renamedPath) || FileManager.default.fileExists(atPath: fullAudioPath)
        XCTAssertTrue(exists)
    }

    // MARK: - Persistence task tests

    func testPersistenceTaskEncodesAndSavesChunk() async {
        let (pipeline, frameContinuation, chunkContinuation) = makePipeline()
        pipeline.startCoroutines()

        let chunk = AudioChunk(
            chunkId: "chunk-1",
            sessionId: "test-session",
            index: 0,
            frames: [makeFrame(timestampMs: 0)],
            startTimeMs: 0,
            endTimeMs: 1000,
            quality: nil
        )
        chunkContinuation.yield(chunk)
        chunkContinuation.finish()
        frameContinuation.finish()

        _ = await pipeline.stop()

        // Verify chunk was saved to data manager
        let savedChunks = try? await dataManager.getAllChunks(sessionId: "test-session")
        XCTAssertEqual(savedChunks?.count, 1)
        XCTAssertEqual(savedChunks?.first?.chunkId, "chunk-1")
    }

    func testPersistenceTaskUploadSuccess() async {
        uploader.uploadResult = .success(url: "s3://bucket/file.m4a")

        let (pipeline, frameContinuation, chunkContinuation) = makePipeline()
        pipeline.startCoroutines()

        let chunk = AudioChunk(
            chunkId: "chunk-ok",
            sessionId: "test-session",
            index: 0,
            frames: [makeFrame()],
            startTimeMs: 0,
            endTimeMs: 1000,
            quality: nil
        )
        chunkContinuation.yield(chunk)
        chunkContinuation.finish()
        frameContinuation.finish()

        _ = await pipeline.stop()

        let saved = dataManager.chunks["chunk-ok"]
        XCTAssertEqual(saved?.uploadState, UploadState.success.rawValue)
        XCTAssertEqual(uploader.uploadCallCount, 1)
    }

    func testPersistenceTaskUploadFailure() async {
        uploader.uploadResult = .failure(error: "network down", isRetryable: true)
        var firedEvent: SessionEventName?

        let (pipeline, frameContinuation, chunkContinuation) = makePipeline { name, _, _, _ in
            firedEvent = name
        }
        pipeline.startCoroutines()

        let chunk = AudioChunk(
            chunkId: "chunk-fail",
            sessionId: "test-session",
            index: 0,
            frames: [makeFrame()],
            startTimeMs: 0,
            endTimeMs: 1000,
            quality: nil
        )
        chunkContinuation.yield(chunk)
        chunkContinuation.finish()
        frameContinuation.finish()

        _ = await pipeline.stop()

        let saved = dataManager.chunks["chunk-fail"]
        XCTAssertEqual(saved?.uploadState, UploadState.failed.rawValue)
        XCTAssertEqual(firedEvent, .chunkUploadFailed)
    }

    // MARK: - stop() tests

    func testStopReturnsFullAudio() async {
        let (pipeline, frameContinuation, _) = makePipeline()
        pipeline.startCoroutines()

        // Feed a frame so there's PCM data to encode
        frameContinuation.yield(makeFrame(pcm: Array(repeating: 1000, count: 512), timestampMs: 0))
        frameContinuation.finish()

        let result = await pipeline.stop()

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.filePath.contains("test-session_full_audio"))
        XCTAssertTrue(recorder.stopCalled)
        XCTAssertTrue(analyser.releaseCalled)
        XCTAssertTrue(chunker.releaseCalled)
    }

    func testStopEmptyRecordingReturnsNil() async {
        let (pipeline, frameContinuation, _) = makePipeline()
        pipeline.startCoroutines()

        // No frames — finish immediately
        frameContinuation.finish()

        let result = await pipeline.stop()
        XCTAssertNil(result)
    }

    func testStopEncoderFailureReturnsNil() async {
        encoder.encodeFromFileError = ScribeException(code: .encoderFailed, message: "encode failed")
        var firedEvent: SessionEventName?

        let (pipeline, frameContinuation, _) = makePipeline { name, _, _, _ in
            firedEvent = name
        }
        pipeline.startCoroutines()

        frameContinuation.yield(makeFrame(pcm: Array(repeating: 1000, count: 512), timestampMs: 0))
        frameContinuation.finish()

        let result = await pipeline.stop()

        XCTAssertNil(result)
        XCTAssertEqual(firedEvent, .fullAudioGenerationFailed)
    }

    // MARK: - pause/resume

    func testPauseAndResume() {
        let (pipeline, _, _) = makePipeline()
        pipeline.start()

        pipeline.pause()
        XCTAssertTrue(recorder.pauseCalled)

        pipeline.resume()
        XCTAssertTrue(recorder.resumeCalled)
    }
}
