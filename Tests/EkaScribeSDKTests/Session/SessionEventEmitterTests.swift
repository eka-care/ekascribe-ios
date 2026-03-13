import XCTest
@testable import EkaScribeSDK

final class SessionEventEmitterTests: XCTestCase {

    func testEmitCallsDelegate() {
        let delegate = MockEkaScribeDelegate()
        let emitter = SessionEventEmitter(delegate: delegate, scribe: EkaScribe.shared, sessionId: "s1")

        emitter.emit(.recordingStarted, .success, "Recording started", ["key": "value"])

        XCTAssertEqual(delegate.emittedEvents.count, 1)
        let event = delegate.emittedEvents[0]
        XCTAssertEqual(event.sessionId, "s1")
        XCTAssertEqual(event.eventName, .recordingStarted)
        XCTAssertEqual(event.eventType, .success)
        XCTAssertEqual(event.message, "Recording started")
        XCTAssertEqual(event.metadata["key"], "value")
        XCTAssertTrue(event.timestampMs > 0)
    }

    func testEmitWithNoMetadata() {
        let delegate = MockEkaScribeDelegate()
        let emitter = SessionEventEmitter(delegate: delegate, scribe: EkaScribe.shared, sessionId: "s2")

        emitter.emit(.sessionPaused, .info, "Paused")

        XCTAssertEqual(delegate.emittedEvents.count, 1)
        XCTAssertTrue(delegate.emittedEvents[0].metadata.isEmpty)
    }

    func testEmitWithNilDelegateDoesNotCrash() {
        let emitter = SessionEventEmitter(delegate: nil, scribe: EkaScribe.shared, sessionId: "s3")
        emitter.emit(.sessionFailed, .error, "Error")
        // No crash = pass
    }

    func testMultipleEmissions() {
        let delegate = MockEkaScribeDelegate()
        let emitter = SessionEventEmitter(delegate: delegate, scribe: EkaScribe.shared, sessionId: "s4")

        emitter.emit(.sessionStartInitiated, .info, "Starting")
        emitter.emit(.recordingStarted, .success, "Started")
        emitter.emit(.sessionStopInitiated, .info, "Stopping")

        XCTAssertEqual(delegate.emittedEvents.count, 3)
        XCTAssertEqual(delegate.emittedEvents[0].eventName, .sessionStartInitiated)
        XCTAssertEqual(delegate.emittedEvents[1].eventName, .recordingStarted)
        XCTAssertEqual(delegate.emittedEvents[2].eventName, .sessionStopInitiated)
    }
}
