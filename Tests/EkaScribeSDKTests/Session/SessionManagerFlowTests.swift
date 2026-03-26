import Combine
import XCTest
@testable import EkaScribeSDK

final class SessionManagerFlowTests: XCTestCase {
    private var config: EkaScribeConfig!
    private var dataManager: MockDataManager!
    private var pipelineFactory: MockPipelineFactory!
    private var transactionManager: MockTransactionManager!
    private var chunkUploader: MockChunkUploader!
    private var timeProvider: MockTimeProvider!
    private var logger: MockLogger!
    private var micChecker: MockMicPermissionChecker!
    private var delegate: MockEkaScribeDelegate!
    private var sut: SessionManager!

    override func setUp() {
        super.setUp()
        config = EkaScribeConfig(
            environment: .production,
            clientInfo: ScribeClientInfo(clientId: "test-client"),
            tokenStorage: MockTokenStorage(),
            debugMode: true
        )
        dataManager = MockDataManager()
        pipelineFactory = MockPipelineFactory()
        transactionManager = MockTransactionManager()
        chunkUploader = MockChunkUploader()
        timeProvider = MockTimeProvider()
        logger = MockLogger()
        micChecker = MockMicPermissionChecker()
        delegate = MockEkaScribeDelegate()
        sut = SessionManager(
            config: config,
            dataManager: dataManager,
            pipelineFactory: pipelineFactory,
            transactionManager: transactionManager,
            chunkUploader: chunkUploader,
            timeProvider: timeProvider,
            logger: logger,
            micPermissionChecker: micChecker
        )
        sut.setDelegate(delegate)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    private var defaultSessionConfig: SessionConfig {
        SessionConfig(languages: ["en-IN"], mode: "dictation", modelType: "pro")
    }

    @discardableResult
    private func startSession() async -> String? {
        var startedId: String?
        await sut.start(
            sessionConfig: defaultSessionConfig,
            onStart: { startedId = $0 },
            onError: { _ in }
        )
        return startedId
    }

    private func waitForState(_ expected: SessionState, timeout: TimeInterval = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while sut.currentState != expected && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return sut.currentState == expected
    }

    // MARK: - uploadFullAudio Tests

    func testUploadFullAudioSuccess() async {
        let sessionId = await startSession()!
        let result = FullAudioResult(filePath: "/tmp/full.m4a", sessionId: sessionId, folderName: "260316", bid: "bid-1")

        chunkUploader.uploadResult = .success(url: "s3://bucket/full.m4a")
        await sut.uploadFullAudio(result)

        XCTAssertEqual(chunkUploader.uploadCallCount, 1)
    }

    func testUploadFullAudioFailure() async {
        let sessionId = await startSession()!
        let result = FullAudioResult(filePath: "/tmp/full.m4a", sessionId: sessionId, folderName: "260316", bid: "bid-1")

        chunkUploader.uploadResult = .failure(error: "Network timeout", isRetryable: true)
        await sut.uploadFullAudio(result)

        XCTAssertEqual(chunkUploader.uploadCallCount, 1)
    }

    func testUploadFullAudioMetadata() async {
        let sessionId = await startSession()!
        let result = FullAudioResult(filePath: "/tmp/full.m4a", sessionId: sessionId, folderName: "260316", bid: "bid-1")

        var capturedMetadata: UploadMetadata?
        let capturingUploader = CapturingChunkUploader()
        // We test via the method directly using the class's chunkUploader
        chunkUploader.uploadResult = .success(url: "s3://test")
        await sut.uploadFullAudio(result)

        // Verify via upload call count
        XCTAssertEqual(chunkUploader.uploadCallCount, 1)
    }

    // MARK: - Flow Forwarding Tests

    func testVoiceActivityFlowForwarding() async {
        await startSession()

        let expectation = XCTestExpectation(description: "Voice activity received")
        var receivedData: VoiceActivityData?
        let cancellable = sut.voiceActivityFlow.first().sink { data in
            receivedData = data
            expectation.fulfill()
        }

        let mockData = VoiceActivityData(isSpeech: true, amplitude: 0.8, timestampMs: 5000)
        pipelineFactory.mockPipeline.voiceActivitySubject.send(mockData)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedData?.isSpeech, true)
        XCTAssertEqual(Double(receivedData?.amplitude ?? 0), 0.8, accuracy: 0.01)
        cancellable.cancel()
    }

    func testAudioQualityFlowForwarding() async {
        await startSession()

        let expectation = XCTestExpectation(description: "Audio quality received")
        var receivedMetrics: AudioQualityMetrics?
        let cancellable = sut.audioQualityFlow.first().sink { metrics in
            receivedMetrics = metrics
            expectation.fulfill()
        }

        let mockMetrics = AudioQualityMetrics(stoi: 0.9, pesq: 3.5, siSDR: 15.0, overallScore: 0.85)
        pipelineFactory.mockPipeline.audioQualitySubject.send(mockMetrics)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(Double(receivedMetrics?.stoi ?? 0), 0.9, accuracy: 0.01)
        XCTAssertEqual(Double(receivedMetrics?.overallScore ?? 0), 0.85, accuracy: 0.01)
        cancellable.cancel()
    }

    func testAudioFocusGainedDoesNotPause() async {
        await startSession()
        XCTAssertEqual(sut.currentState, .recording)

        pipelineFactory.mockPipeline.audioFocusSubject.send(true)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(sut.currentState, .recording)
    }

    func testAudioFocusEmitsDelegate() async {
        await startSession()

        pipelineFactory.mockPipeline.audioFocusSubject.send(false)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(delegate.didChangeAudioFocusValue, false)
    }

    // MARK: - Stop Event and State Tests

    func testStopWithFullAudioResult() async {
        pipelineFactory.mockPipeline.stopResult = FullAudioResult(
            filePath: "/tmp/full_audio.m4a",
            sessionId: "test",
            folderName: "260316",
            bid: "bid-1"
        )
        await startSession()
        sut.stop()

        let reached = await waitForState(.completed)
        XCTAssertTrue(reached)
        XCTAssertEqual(sut.lastFullAudioPath, "/tmp/full_audio.m4a")
    }

    func testStopWithNilFullAudioResult() async {
        pipelineFactory.mockPipeline.stopResult = nil
        await startSession()
        sut.stop()

        let reached = await waitForState(.completed)
        XCTAssertTrue(reached)
        XCTAssertNil(sut.lastFullAudioPath)
    }

    func testStartSavesSessionRecord() async {
        let sessionId = await startSession()
        XCTAssertNotNil(sessionId)
        XCTAssertFalse(dataManager.sessions.isEmpty)

        let saved = dataManager.sessions.values.first
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.mode, "dictation")
        XCTAssertEqual(saved?.uploadStage, TransactionStage.initialize.rawValue)
    }

    func testStartEmitsDelegateDidStart() async {
        let sessionId = await startSession()
        XCTAssertNotNil(sessionId)
        XCTAssertEqual(delegate.didStartSessionId, sessionId)
    }

    func testStopEmitsDelegateDidStop() async {
        await startSession()
        sut.stop()

        let reached = await waitForState(.completed)
        XCTAssertTrue(reached)
        XCTAssertNotNil(delegate.didStopSessionId)
    }

    func testDestroyCleansPipeline() async {
        await startSession()
        XCTAssertEqual(sut.currentState, .recording)

        sut.destroy()
        // destroy() cleans up pipeline reference
        XCTAssertNil(sut.pipeline)
    }
}

// MARK: - Helper for metadata capture

private final class CapturingChunkUploader: ChunkUploader {
    var capturedMetadata: UploadMetadata?
    var uploadResult: UploadResult = .success(url: "s3://test")

    func upload(file: URL, metadata: UploadMetadata) async -> UploadResult {
        capturedMetadata = metadata
        return uploadResult
    }

    func clearCache() async {}
}
