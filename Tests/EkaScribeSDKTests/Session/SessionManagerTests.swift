import Combine
import XCTest
@testable import EkaScribeSDK

final class SessionManagerTests: XCTestCase {
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
            baseURL: "https://test.example.com",
            credentialsURL: "https://creds.example.com",
            bucketName: "test-bucket",
            authTokenProvider: { "test-token" },
            debugMode: true,
            pollMaxRetries: 3,
            pollDelayMs: 10
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

    // MARK: - Helpers

    /// Starts a session and returns the session ID provided via onStart callback.
    @discardableResult
    private func startSession(sessionConfig: SessionConfig = SessionConfig()) async -> String? {
        var startedId: String?
        await sut.start(
            sessionConfig: sessionConfig,
            onStart: { startedId = $0 },
            onError: { _ in }
        )
        return startedId
    }

    /// Waits for the SessionManager state to reach the expected value (with timeout).
    private func waitForState(_ expected: SessionState, timeout: TimeInterval = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while sut.currentState != expected && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        return sut.currentState == expected
    }

    // MARK: - start() tests

    func testStartSuccessful() async {
        var startedId: String?
        await sut.start(
            sessionConfig: SessionConfig(),
            onStart: { startedId = $0 },
            onError: { XCTFail("Unexpected error: \($0.message)") }
        )

        XCTAssertEqual(sut.currentState, .recording)
        XCTAssertNotNil(startedId)
        XCTAssertNotNil(delegate.didStartSessionId)
        XCTAssertEqual(startedId, delegate.didStartSessionId)
        XCTAssertEqual(pipelineFactory.createCallCount, 1)
        XCTAssertTrue(pipelineFactory.mockPipeline.startCalled)
        XCTAssertEqual(transactionManager.initCallCount, 1)
    }

    func testStartMicDenied() async {
        micChecker.permissionGranted = false
        var receivedError: ScribeError?

        await sut.start(
            sessionConfig: SessionConfig(),
            onStart: { _ in XCTFail("Should not start") },
            onError: { receivedError = $0 }
        )

        XCTAssertEqual(sut.currentState, .idle)
        XCTAssertEqual(receivedError?.code, .micPermissionDenied)
        XCTAssertEqual(transactionManager.initCallCount, 0)
    }

    func testStartAlreadyRecording() async {
        // Start first session
        await startSession()
        XCTAssertEqual(sut.currentState, .recording)

        // Try starting again while recording
        var receivedError: ScribeError?
        await sut.start(
            sessionConfig: SessionConfig(),
            onStart: { _ in XCTFail("Should not start") },
            onError: { receivedError = $0 }
        )

        XCTAssertEqual(receivedError?.code, .sessionAlreadyActive)
        XCTAssertEqual(sut.currentState, .recording)
        // Pipeline should only have been created once
        XCTAssertEqual(pipelineFactory.createCallCount, 1)
    }

    func testStartFromCompletedResets() async {
        // First session
        await startSession()
        XCTAssertEqual(sut.currentState, .recording)

        // Simulate session completing by calling stop and waiting
        sut.stop()
        let reached = await waitForState(.completed)
        XCTAssertTrue(reached, "Expected completed state, got \(sut.currentState.rawValue)")

        // Start new session from completed state
        let newId = await startSession()
        XCTAssertEqual(sut.currentState, .recording)
        XCTAssertNotNil(newId)
        // Pipeline factory should have been called again
        XCTAssertEqual(pipelineFactory.createCallCount, 2)
    }

    func testStartInitFails() async {
        transactionManager.initResult = .error(message: "Server down")
        var receivedError: ScribeError?

        await sut.start(
            sessionConfig: SessionConfig(),
            onStart: { _ in XCTFail("Should not start") },
            onError: { receivedError = $0 }
        )

        XCTAssertEqual(sut.currentState, .error)
        XCTAssertEqual(receivedError?.code, .initTransactionFailed)
        XCTAssertEqual(receivedError?.message, "Server down")
        XCTAssertNotNil(delegate.didFailError)
        XCTAssertEqual(delegate.didFailError?.code, .initTransactionFailed)
        XCTAssertEqual(pipelineFactory.createCallCount, 0)
    }

    func testStartFromErrorResets() async {
        // Trigger error state
        transactionManager.initResult = .error(message: "fail")
        await startSession()
        XCTAssertEqual(sut.currentState, .error)

        // Now fix the mock and start again
        transactionManager.initResult = .success(folderName: "240101", bid: "bid-2")
        let newId = await startSession()

        XCTAssertEqual(sut.currentState, .recording)
        XCTAssertNotNil(newId)
        XCTAssertEqual(transactionManager.initCallCount, 2)
    }

    // MARK: - pause() tests

    func testPauseFromRecording() async {
        await startSession()
        XCTAssertEqual(sut.currentState, .recording)

        sut.pause()

        XCTAssertEqual(sut.currentState, .paused)
        XCTAssertTrue(pipelineFactory.mockPipeline.pauseCalled)
        XCTAssertNotNil(delegate.didPauseSessionId)
    }

    func testPauseFromNonRecordingNoOp() async {
        // State is idle, pause should do nothing
        sut.pause()

        XCTAssertEqual(sut.currentState, .idle)
        XCTAssertFalse(pipelineFactory.mockPipeline.pauseCalled)
        XCTAssertNil(delegate.didPauseSessionId)
    }

    // MARK: - resume() tests

    func testResumeFromPaused() async {
        await startSession()
        sut.pause()
        XCTAssertEqual(sut.currentState, .paused)

        sut.resume()

        XCTAssertEqual(sut.currentState, .recording)
        XCTAssertTrue(pipelineFactory.mockPipeline.resumeCalled)
        XCTAssertNotNil(delegate.didResumeSessionId)
    }

    func testResumeFromNonPausedNoOp() async {
        await startSession()
        XCTAssertEqual(sut.currentState, .recording)

        // Resume while recording should be a no-op
        sut.resume()

        XCTAssertEqual(sut.currentState, .recording)
        XCTAssertFalse(pipelineFactory.mockPipeline.resumeCalled)
        XCTAssertNil(delegate.didResumeSessionId)
    }

    // MARK: - stop() tests

    func testStopHappyPath() async {
        await startSession()

        sut.stop()

        let reached = await waitForState(.completed)
        XCTAssertTrue(reached, "Expected completed state, got \(sut.currentState.rawValue)")

        XCTAssertTrue(pipelineFactory.mockPipeline.stopCalled)
        XCTAssertNotNil(delegate.didStopSessionId)
        XCTAssertEqual(transactionManager.retryCallCount, 1)
        XCTAssertEqual(transactionManager.stopCallCount, 1)
        XCTAssertEqual(transactionManager.commitCallCount, 1)
        XCTAssertEqual(transactionManager.pollCallCount, 1)
        XCTAssertNotNil(delegate.didCompleteSessionId)
    }

    func testStopRetryFails() async {
        transactionManager.retryResult = false
        await startSession()

        sut.stop()

        let reached = await waitForState(.error)
        XCTAssertTrue(reached, "Expected error state, got \(sut.currentState.rawValue)")

        XCTAssertNotNil(delegate.didFailError)
        XCTAssertEqual(delegate.didFailError?.code, .retryExhausted)
        // Should not proceed to stop/commit/poll
        XCTAssertEqual(transactionManager.stopCallCount, 0)
        XCTAssertEqual(transactionManager.commitCallCount, 0)
        XCTAssertEqual(transactionManager.pollCallCount, 0)
    }

    func testStopTransactionFails() async {
        transactionManager.stopResult = .error(message: "stop server error")
        await startSession()

        sut.stop()

        let reached = await waitForState(.error)
        XCTAssertTrue(reached, "Expected error state, got \(sut.currentState.rawValue)")

        XCTAssertNotNil(delegate.didFailError)
        XCTAssertEqual(delegate.didFailError?.code, .stopTransactionFailed)
        XCTAssertEqual(delegate.didFailError?.message, "stop server error")
        // Should not proceed to commit/poll
        XCTAssertEqual(transactionManager.commitCallCount, 0)
        XCTAssertEqual(transactionManager.pollCallCount, 0)
    }

    func testStopCommitFails() async {
        transactionManager.commitResult = .error(message: "commit failure")
        await startSession()

        sut.stop()

        let reached = await waitForState(.error)
        XCTAssertTrue(reached, "Expected error state, got \(sut.currentState.rawValue)")

        XCTAssertNotNil(delegate.didFailError)
        XCTAssertEqual(delegate.didFailError?.code, .commitTransactionFailed)
        XCTAssertEqual(transactionManager.pollCallCount, 0)
    }

    func testStopPollTimeout() async {
        transactionManager.pollResult = .timeout
        await startSession()

        sut.stop()

        let reached = await waitForState(.completed)
        XCTAssertTrue(reached, "Expected completed state (timeout is not error), got \(sut.currentState.rawValue)")
    }

    func testStopPollFailed() async {
        transactionManager.pollResult = .failed(error: "transcription error")
        await startSession()

        sut.stop()

        let reached = await waitForState(.error)
        XCTAssertTrue(reached, "Expected error state, got \(sut.currentState.rawValue)")

        XCTAssertNotNil(delegate.didFailError)
        XCTAssertEqual(delegate.didFailError?.code, .transcriptionFailed)
    }

    func testStopCleanupAlwaysRuns() async {
        await startSession()
        XCTAssertNotNil(sut.pipeline)

        sut.stop()

        let reached = await waitForState(.completed)
        XCTAssertTrue(reached)

        // Pipeline should be nil after cleanup
        XCTAssertNil(sut.pipeline)
    }

    func testStopCleanupRunsOnError() async {
        transactionManager.retryResult = false
        await startSession()
        XCTAssertNotNil(sut.pipeline)

        sut.stop()

        let reached = await waitForState(.error)
        XCTAssertTrue(reached)

        // Pipeline should be nil after cleanup even on error
        XCTAssertNil(sut.pipeline)
    }

    func testStopFromIdleNoOp() {
        sut.stop()

        XCTAssertEqual(sut.currentState, .idle)
        XCTAssertFalse(pipelineFactory.mockPipeline.stopCalled)
    }

    func testStopFromPausedState() async {
        await startSession()
        sut.pause()
        XCTAssertEqual(sut.currentState, .paused)

        sut.stop()

        let reached = await waitForState(.completed)
        XCTAssertTrue(reached, "Expected completed state from paused stop, got \(sut.currentState.rawValue)")
        XCTAssertTrue(pipelineFactory.mockPipeline.stopCalled)
    }

    // MARK: - destroy() tests

    func testDestroy() async {
        await startSession()
        XCTAssertEqual(sut.currentState, .recording)

        sut.destroy()

        XCTAssertEqual(sut.currentState, .idle)
        XCTAssertNil(sut.pipeline)
    }

    // MARK: - Audio focus tests

    func testAudioFocusLostCausesPause() async {
        await startSession()
        XCTAssertEqual(sut.currentState, .recording)

        // Simulate audio focus loss via the mock pipeline's subject
        pipelineFactory.mockPipeline.audioFocusSubject.send(false)

        // Give the Combine pipeline a moment to process
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(sut.currentState, .paused)
        XCTAssertTrue(pipelineFactory.mockPipeline.pauseCalled)
        XCTAssertEqual(delegate.didChangeAudioFocusValue, false)
    }

    // MARK: - mapToSessionResult tests

    func testMapToSessionResultBasic() {
        let output = ScribeResultResponse.OutputDTO(
            errors: nil, name: "SOAP Note", status: .success,
            templateId: "tmpl-1", type: "markdown", value: nil, warnings: nil
        )
        let response = ScribeResultResponse(data: ScribeResultResponse.ResultData(
            audioMatrix: nil, createdAt: nil, output: [output], templateResults: nil
        ))

        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertEqual(result.templates.count, 1)
        XCTAssertEqual(result.templates.first?.name, "SOAP Note")
        XCTAssertEqual(result.templates.first?.templateId, "tmpl-1")
        XCTAssertEqual(result.templates.first?.type, .markdown)
    }

    func testMapToSessionResultEmptyOutput() {
        let response = ScribeResultResponse(data: ScribeResultResponse.ResultData(
            audioMatrix: nil, createdAt: nil, output: [], templateResults: nil
        ))

        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertTrue(result.templates.isEmpty)
    }

    func testMapToSessionResultNilData() {
        let response = ScribeResultResponse(data: nil)

        let result = SessionManager.mapToSessionResult(sessionId: "s1", response)

        XCTAssertTrue(result.templates.isEmpty)
    }
}
