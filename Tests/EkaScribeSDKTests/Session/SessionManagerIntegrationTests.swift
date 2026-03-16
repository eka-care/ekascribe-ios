import Combine
import XCTest
@testable import EkaScribeSDK

final class SessionManagerIntegrationTests: XCTestCase {
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
    private func startSession(sessionConfig: SessionConfig? = nil) async -> String? {
        var startedId: String?
        await sut.start(
            sessionConfig: sessionConfig ?? defaultSessionConfig,
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

    // MARK: - Full Lifecycle Integration Tests

    func testFullRecordingLifecycleHappyPath() async {
        // Start recording
        let sessionId = await startSession()
        XCTAssertNotNil(sessionId)
        XCTAssertEqual(sut.currentState, .recording)
        XCTAssertNotNil(delegate.didStartSessionId)

        // Pause
        sut.pause()
        XCTAssertEqual(sut.currentState, .paused)
        XCTAssertNotNil(delegate.didPauseSessionId)

        // Resume
        sut.resume()
        XCTAssertEqual(sut.currentState, .recording)
        XCTAssertNotNil(delegate.didResumeSessionId)

        // Stop (triggers transaction flow)
        transactionManager.pollResult = .success(result: ScribeResultResponse(data: nil))
        sut.stop()

        let completed = await waitForState(.completed)
        XCTAssertTrue(completed, "Expected completed state")
        XCTAssertNotNil(delegate.didStopSessionId)
        XCTAssertNotNil(delegate.didCompleteSessionId)
    }

    func testRecordingWithInitTransactionFailure() async {
        transactionManager.initResult = .error(message: "Server unavailable")

        var receivedError: ScribeError?
        await sut.start(
            sessionConfig: defaultSessionConfig,
            onStart: { _ in },
            onError: { receivedError = $0 }
        )

        XCTAssertEqual(sut.currentState, .error)
        XCTAssertNotNil(receivedError)
        XCTAssertEqual(receivedError?.code, .initTransactionFailed)
        XCTAssertNotNil(delegate.didFailError)
    }

    func testRecordingWithUploadRetryExhaustion() async {
        transactionManager.retryResult = false

        await startSession()
        sut.stop()

        let errorReached = await waitForState(.error)
        XCTAssertTrue(errorReached, "Expected error state after retry exhaustion")
        XCTAssertNotNil(delegate.didFailError)
        XCTAssertEqual(delegate.didFailError?.code, .retryExhausted)
    }

    func testRecordingWithStopTransactionFailure() async {
        transactionManager.stopResult = .error(message: "Stop failed")

        await startSession()
        sut.stop()

        let errorReached = await waitForState(.error)
        XCTAssertTrue(errorReached)
        XCTAssertEqual(delegate.didFailError?.code, .stopTransactionFailed)
    }

    func testRecordingWithCommitFailure() async {
        transactionManager.commitResult = .error(message: "Commit failed")

        await startSession()
        sut.stop()

        let errorReached = await waitForState(.error)
        XCTAssertTrue(errorReached)
        XCTAssertEqual(delegate.didFailError?.code, .commitTransactionFailed)
    }

    func testRecordingWithPollFailure() async {
        transactionManager.pollResult = .failed(error: "Transcription processing failed")

        await startSession()
        sut.stop()

        let errorReached = await waitForState(.error)
        XCTAssertTrue(errorReached)
        XCTAssertEqual(delegate.didFailError?.code, .transcriptionFailed)
    }

    func testRecordingWithPollTimeout() async {
        transactionManager.pollResult = .timeout

        await startSession()
        sut.stop()

        // Poll timeout transitions to completed (not error)
        let completedReached = await waitForState(.completed)
        XCTAssertTrue(completedReached, "Poll timeout should result in completed state")
    }

    func testStartFromCompletedState() async {
        // Complete first session
        await startSession()
        sut.stop()
        let completed = await waitForState(.completed)
        XCTAssertTrue(completed)

        // Start new session from completed state
        let newSessionId = await startSession()
        XCTAssertNotNil(newSessionId)
        XCTAssertEqual(sut.currentState, .recording)
    }

    func testStartFromErrorState() async {
        // Trigger error
        transactionManager.retryResult = false
        await startSession()
        sut.stop()
        let errorReached = await waitForState(.error)
        XCTAssertTrue(errorReached)

        // Reset mocks for success
        transactionManager.retryResult = true
        transactionManager.pollResult = .success(result: ScribeResultResponse(data: nil))

        // Start new session from error state
        let newSessionId = await startSession()
        XCTAssertNotNil(newSessionId)
        XCTAssertEqual(sut.currentState, .recording)
    }

    func testMicPermissionDeniedFlow() async {
        micChecker.permissionGranted = false

        var receivedError: ScribeError?
        await sut.start(
            sessionConfig: defaultSessionConfig,
            onStart: { _ in XCTFail("Should not start") },
            onError: { receivedError = $0 }
        )

        XCTAssertEqual(sut.currentState, .idle)
        XCTAssertEqual(receivedError?.code, .micPermissionDenied)
    }
}
