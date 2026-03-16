import XCTest
@testable import EkaScribeSDK

final class LoggerTests: XCTestCase {

    // MARK: - DefaultLogger Tests

    func testDefaultLoggerDebugDoesNotCrash() {
        let logger = DefaultLogger()
        logger.debug("TestTag", "Debug message")
    }

    func testDefaultLoggerInfoDoesNotCrash() {
        let logger = DefaultLogger()
        logger.info("TestTag", "Info message")
    }

    func testDefaultLoggerWarnWithError() {
        let logger = DefaultLogger()
        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        logger.warn("TestTag", "Warning with error", error)
    }

    func testDefaultLoggerWarnWithNilError() {
        let logger = DefaultLogger()
        logger.warn("TestTag", "Warning without error", nil)
    }

    func testDefaultLoggerErrorWithError() {
        let logger = DefaultLogger()
        let error = NSError(domain: "test", code: 1)
        logger.error("TestTag", "Error message", error)
    }

    func testDefaultLoggerErrorWithNilError() {
        let logger = DefaultLogger()
        logger.error("TestTag", "Error without cause", nil)
    }

    // MARK: - NoOpLogger Tests

    func testNoOpLoggerDebug() {
        let logger = NoOpLogger()
        logger.debug("Tag", "Message")
    }

    func testNoOpLoggerInfo() {
        let logger = NoOpLogger()
        logger.info("Tag", "Message")
    }

    func testNoOpLoggerWarn() {
        let logger = NoOpLogger()
        logger.warn("Tag", "Message", nil)
    }

    func testNoOpLoggerError() {
        let logger = NoOpLogger()
        logger.error("Tag", "Message", NSError(domain: "t", code: 0))
    }

    // MARK: - MockLogger Tests

    func testMockLoggerCapturesEntries() {
        let logger = MockLogger()

        logger.debug("D", "debug msg")
        logger.info("I", "info msg")
        logger.warn("W", "warn msg", nil)
        logger.error("E", "error msg", nil)

        XCTAssertEqual(logger.entries.count, 4)
        XCTAssertEqual(logger.entries[0].level, "debug")
        XCTAssertEqual(logger.entries[0].tag, "D")
        XCTAssertEqual(logger.entries[0].message, "debug msg")
        XCTAssertEqual(logger.entries[1].level, "info")
        XCTAssertEqual(logger.entries[2].level, "warn")
        XCTAssertEqual(logger.entries[3].level, "error")
    }

    func testMockLoggerThreadSafety() {
        let logger = MockLogger()
        let group = DispatchGroup()

        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                logger.info("Thread", "Message \(i)")
                group.leave()
            }
        }

        group.wait()
        XCTAssertEqual(logger.entries.count, 100)
    }
}
