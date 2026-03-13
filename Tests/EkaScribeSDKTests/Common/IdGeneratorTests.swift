import XCTest
@testable import EkaScribeSDK

final class IdGeneratorTests: XCTestCase {

    func testSessionIdHasPrefix() {
        let id = IdGenerator.sessionId()
        XCTAssertTrue(id.hasPrefix("test-ios-"), "Session ID should start with 'test-ios-', got: \(id)")
    }

    func testSessionIdContainsUUID() {
        let id = IdGenerator.sessionId()
        let uuidPart = String(id.dropFirst("test-ios-".count))
        XCTAssertEqual(uuidPart.count, 36, "UUID part should be 36 chars (with hyphens)")
        XCTAssertEqual(uuidPart, uuidPart.lowercased(), "UUID in session ID should be lowercased")
    }

    func testSessionIdUniqueness() {
        let id1 = IdGenerator.sessionId()
        let id2 = IdGenerator.sessionId()
        XCTAssertNotEqual(id1, id2, "Two session IDs should be unique")
    }

    func testChunkIdFormat() {
        let sessionId = "test-ios-abc"
        let chunkId = IdGenerator.chunkId(sessionId: sessionId, index: 3)
        XCTAssertEqual(chunkId, "test-ios-abc_3")
    }

    func testChunkIdZeroIndex() {
        let chunkId = IdGenerator.chunkId(sessionId: "session-1", index: 0)
        XCTAssertEqual(chunkId, "session-1_0")
    }
}
