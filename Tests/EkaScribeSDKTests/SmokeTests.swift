import XCTest
@testable import EkaScribeSDK

final class SmokeTests: XCTestCase {
    func testLibraryLoads() {
        XCTAssertNotNil(EkaScribe.shared)
    }
}
