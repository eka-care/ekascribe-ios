import XCTest
@testable import EkaScribeSDK

final class SmokeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        EkaScribe.shared.destroy()
    }

    override func tearDown() {
        EkaScribe.shared.destroy()
        super.tearDown()
    }

    func testLibraryLoads() {
        XCTAssertNotNil(EkaScribe.shared)
    }

    func testGetSessionStateThrowsWhenSDKNotInitialized() {
        XCTAssertThrowsError(try EkaScribe.shared.getSessionState()) { error in
            let scribeError = error as? ScribeError
            XCTAssertEqual(scribeError?.code, .invalidConfig)
            XCTAssertEqual(scribeError?.message, "EkaScribe SDK not initialized. Call initialize() first.")
        }
    }

    func testStartSessionThrowsWhenSDKNotInitialized() async {
        do {
            try await EkaScribe.shared.startSession(config: SessionConfig(languages: ["en-IN"], mode: "dictation", modelType: "pro"))
            XCTFail("Expected startSession to throw when SDK is not initialized")
        } catch let error as ScribeError {
            XCTAssertEqual(error.code, .invalidConfig)
            XCTAssertEqual(error.message, "EkaScribe SDK not initialized. Call initialize() first.")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPollSessionResultReturnsInitializationErrorWhenSDKNotInitialized() async {
        let result = await EkaScribe.shared.pollSessionResult("session-id")

        switch result {
        case .success:
            XCTFail("Expected pollSessionResult to fail when SDK is not initialized")
        case .failure(let error as ScribeError):
            XCTAssertEqual(error.code, .invalidConfig)
            XCTAssertEqual(error.message, "EkaScribe SDK not initialized. Call initialize() first.")
        case .failure(let error):
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
