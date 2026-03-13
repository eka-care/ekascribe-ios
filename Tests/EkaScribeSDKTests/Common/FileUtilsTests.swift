import XCTest
@testable import EkaScribeSDK

final class FileUtilsTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EkaScribeSDKTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDeleteFileRemovesFile() {
        let filePath = tempDir.appendingPathComponent("test.txt")
        FileManager.default.createFile(atPath: filePath.path, contents: Data("hello".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))

        deleteFile(filePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath.path))
    }

    func testDeleteFileNoErrorOnMissingFile() {
        let missingFile = tempDir.appendingPathComponent("nonexistent.txt")
        // Should not crash
        deleteFile(missingFile, logger: MockLogger())
    }

    func testURLExists() {
        let filePath = tempDir.appendingPathComponent("exists.txt")
        FileManager.default.createFile(atPath: filePath.path, contents: Data("data".utf8))

        XCTAssertTrue(filePath.exists)
        XCTAssertFalse(tempDir.appendingPathComponent("missing.txt").exists)
    }

    func testURLFileSize() {
        let filePath = tempDir.appendingPathComponent("sized.txt")
        let content = Data("twelve chars".utf8) // Known content
        FileManager.default.createFile(atPath: filePath.path, contents: content)

        XCTAssertEqual(filePath.fileSize, content.count)
    }

    func testURLFileSizeMissing() {
        let missingFile = tempDir.appendingPathComponent("missing.txt")
        XCTAssertEqual(missingFile.fileSize, 0)
    }
}
