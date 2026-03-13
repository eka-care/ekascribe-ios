import XCTest
@testable import EkaScribeSDK

final class TimeProviderTests: XCTestCase {

    func testDefaultTimeProviderReturnsPositive() {
        let provider = DefaultTimeProvider()
        XCTAssertGreaterThan(provider.nowMillis(), 0)
    }

    func testDefaultTimeProviderIsMonotonic() {
        let provider = DefaultTimeProvider()
        let t1 = provider.nowMillis()
        let t2 = provider.nowMillis()
        XCTAssertGreaterThanOrEqual(t2, t1)
    }

    func testDefaultTimeProviderIsReasonable() {
        let provider = DefaultTimeProvider()
        let now = provider.nowMillis()
        // Should be after 2024-01-01
        let jan2024: Int = 1_704_067_200_000
        XCTAssertGreaterThan(now, jan2024)
    }

    func testMockTimeProviderReturnsConfiguredValue() {
        let mock = MockTimeProvider()
        mock.currentTime = 42
        XCTAssertEqual(mock.nowMillis(), 42)
    }
}
