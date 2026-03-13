import XCTest
@testable import EkaScribeSDK

final class ChunkConfigTests: XCTestCase {

    func testDefaultValues() {
        let config = ChunkConfig()
        XCTAssertEqual(config.preferredDurationSec, 10)
        XCTAssertEqual(config.desperationDurationSec, 20)
        XCTAssertEqual(config.maxDurationSec, 25)
        XCTAssertEqual(config.longSilenceSec, 0.5)
        XCTAssertEqual(config.shortSilenceSec, 0.1)
        XCTAssertEqual(config.overlapDurationSec, 0.5)
    }

    func testCustomValues() {
        let config = ChunkConfig(
            preferredDurationSec: 5,
            desperationDurationSec: 15,
            maxDurationSec: 30,
            longSilenceSec: 1.0,
            shortSilenceSec: 0.2,
            overlapDurationSec: 0.25
        )
        XCTAssertEqual(config.preferredDurationSec, 5)
        XCTAssertEqual(config.desperationDurationSec, 15)
        XCTAssertEqual(config.maxDurationSec, 30)
        XCTAssertEqual(config.longSilenceSec, 1.0)
        XCTAssertEqual(config.shortSilenceSec, 0.2)
        XCTAssertEqual(config.overlapDurationSec, 0.25)
    }
}
