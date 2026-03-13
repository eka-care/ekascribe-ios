import XCTest
@testable import EkaScribeSDK

final class SessionStateTests: XCTestCase {

    // MARK: - Idle Transitions

    func testIdleCanTransitionToStarting() {
        XCTAssertTrue(SessionState.idle.canTransition(to: .starting))
    }

    func testIdleCannotTransitionToRecording() {
        XCTAssertFalse(SessionState.idle.canTransition(to: .recording))
    }

    func testIdleCannotTransitionToPaused() {
        XCTAssertFalse(SessionState.idle.canTransition(to: .paused))
    }

    func testIdleCannotTransitionToIdle() {
        XCTAssertFalse(SessionState.idle.canTransition(to: .idle))
    }

    // MARK: - Starting Transitions

    func testStartingCanTransitionToRecording() {
        XCTAssertTrue(SessionState.starting.canTransition(to: .recording))
    }

    func testStartingCanTransitionToError() {
        XCTAssertTrue(SessionState.starting.canTransition(to: .error))
    }

    func testStartingCannotTransitionToPaused() {
        XCTAssertFalse(SessionState.starting.canTransition(to: .paused))
    }

    func testStartingCannotTransitionToStopping() {
        XCTAssertFalse(SessionState.starting.canTransition(to: .stopping))
    }

    // MARK: - Recording Transitions

    func testRecordingCanTransitionToPaused() {
        XCTAssertTrue(SessionState.recording.canTransition(to: .paused))
    }

    func testRecordingCanTransitionToStopping() {
        XCTAssertTrue(SessionState.recording.canTransition(to: .stopping))
    }

    func testRecordingCanTransitionToError() {
        XCTAssertTrue(SessionState.recording.canTransition(to: .error))
    }

    func testRecordingCannotTransitionToIdle() {
        XCTAssertFalse(SessionState.recording.canTransition(to: .idle))
    }

    // MARK: - Paused Transitions

    func testPausedCanTransitionToRecording() {
        XCTAssertTrue(SessionState.paused.canTransition(to: .recording))
    }

    func testPausedCanTransitionToStopping() {
        XCTAssertTrue(SessionState.paused.canTransition(to: .stopping))
    }

    func testPausedCannotTransitionToError() {
        XCTAssertFalse(SessionState.paused.canTransition(to: .error))
    }

    // MARK: - Stopping Transitions

    func testStoppingCanTransitionToProcessing() {
        XCTAssertTrue(SessionState.stopping.canTransition(to: .processing))
    }

    func testStoppingCanTransitionToCompleted() {
        XCTAssertTrue(SessionState.stopping.canTransition(to: .completed))
    }

    func testStoppingCanTransitionToError() {
        XCTAssertTrue(SessionState.stopping.canTransition(to: .error))
    }

    func testStoppingCannotTransitionToRecording() {
        XCTAssertFalse(SessionState.stopping.canTransition(to: .recording))
    }

    // MARK: - Processing Transitions

    func testProcessingCanTransitionToCompleted() {
        XCTAssertTrue(SessionState.processing.canTransition(to: .completed))
    }

    func testProcessingCanTransitionToError() {
        XCTAssertTrue(SessionState.processing.canTransition(to: .error))
    }

    func testProcessingCannotTransitionToRecording() {
        XCTAssertFalse(SessionState.processing.canTransition(to: .recording))
    }

    // MARK: - Completed Transitions

    func testCompletedCanTransitionToIdle() {
        XCTAssertTrue(SessionState.completed.canTransition(to: .idle))
    }

    func testCompletedCannotTransitionToRecording() {
        XCTAssertFalse(SessionState.completed.canTransition(to: .recording))
    }

    // MARK: - Error Transitions

    func testErrorCanTransitionToIdle() {
        XCTAssertTrue(SessionState.error.canTransition(to: .idle))
    }

    func testErrorCannotTransitionToRecording() {
        XCTAssertFalse(SessionState.error.canTransition(to: .recording))
    }

    // MARK: - Raw Values

    func testRawValues() {
        XCTAssertEqual(SessionState.idle.rawValue, "idle")
        XCTAssertEqual(SessionState.starting.rawValue, "starting")
        XCTAssertEqual(SessionState.recording.rawValue, "recording")
        XCTAssertEqual(SessionState.paused.rawValue, "paused")
        XCTAssertEqual(SessionState.stopping.rawValue, "stopping")
        XCTAssertEqual(SessionState.processing.rawValue, "processing")
        XCTAssertEqual(SessionState.completed.rawValue, "completed")
        XCTAssertEqual(SessionState.error.rawValue, "error")
    }
}
