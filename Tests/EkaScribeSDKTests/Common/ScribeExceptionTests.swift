import XCTest
@testable import EkaScribeSDK

final class ScribeExceptionTests: XCTestCase {

    func testInitWithAllFields() {
        let cause = NSError(domain: "test", code: 1)
        let exception = ScribeException(code: .encoderFailed, message: "Encoding error", cause: cause)
        XCTAssertEqual(exception.code, .encoderFailed)
        XCTAssertEqual(exception.message, "Encoding error")
        XCTAssertNotNil(exception.cause)
    }

    func testInitWithoutCause() {
        let exception = ScribeException(code: .networkUnavailable, message: "No network")
        XCTAssertEqual(exception.code, .networkUnavailable)
        XCTAssertEqual(exception.message, "No network")
        XCTAssertNil(exception.cause)
    }

    func testConformsToError() {
        let exception: Error = ScribeException(code: .unknown, message: "test")
        XCTAssertTrue(exception is ScribeException)
    }

    func testScribeErrorInit() {
        let error = ScribeError(code: .micPermissionDenied, message: "Mic denied")
        XCTAssertEqual(error.code, .micPermissionDenied)
        XCTAssertEqual(error.message, "Mic denied")
        XCTAssertFalse(error.isRecoverable)
    }

    func testScribeErrorRecoverable() {
        let error = ScribeError(code: .uploadFailed, message: "Upload failed", isRecoverable: true)
        XCTAssertTrue(error.isRecoverable)
    }
}
