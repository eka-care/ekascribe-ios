import XCTest
@testable import EkaScribeSDK

final class TransactionManagerTests: XCTestCase {

    func testDefaultFolderNameFormat() {
        let folderName = TransactionManager.defaultFolderName()
        // Should be 6 characters in yyMMdd format
        XCTAssertEqual(folderName.count, 6)
        // Should be all digits
        XCTAssertTrue(folderName.allSatisfy { $0.isNumber })
    }

    func testDefaultFolderNameMatchesToday() {
        let folderName = TransactionManager.defaultFolderName()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        let expected = formatter.string(from: Date())
        XCTAssertEqual(folderName, expected)
    }

    func testDefaultFolderNameConsistency() {
        // Two calls in succession should return the same value
        let name1 = TransactionManager.defaultFolderName()
        let name2 = TransactionManager.defaultFolderName()
        XCTAssertEqual(name1, name2)
    }
}
