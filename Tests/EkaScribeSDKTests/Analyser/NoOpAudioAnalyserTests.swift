import Combine
import XCTest
@testable import EkaScribeSDK

final class NoOpAudioAnalyserTests: XCTestCase {

    func testSubmitFrameDoesNotCrash() {
        let analyser = NoOpAudioAnalyser()
        analyser.submitFrame(makeFrame())
        // No crash = success
    }

    func testQualityFlowCompletesImmediately() {
        let analyser = NoOpAudioAnalyser()
        let expectation = expectation(description: "Quality flow completes")

        var receivedValues: [AudioQuality] = []
        let cancellable = analyser.qualityFlow
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { receivedValues.append($0) }
            )

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(receivedValues.isEmpty)
        _ = cancellable
    }

    func testReleaseDoesNotCrash() {
        let analyser = NoOpAudioAnalyser()
        analyser.release()
        // No crash = success
    }
}
