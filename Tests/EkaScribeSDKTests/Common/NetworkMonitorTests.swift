import XCTest
@testable import EkaScribeSDK

final class NetworkMonitorTests: XCTestCase {

    func test_mockNetworkMonitor_defaultsToConnected() {
        let mock = MockNetworkMonitor()
        XCTAssertTrue(mock.isConnected)
    }

    func test_mockNetworkMonitor_canBeSetToDisconnected() {
        let mock = MockNetworkMonitor()
        mock.isConnected = false
        XCTAssertFalse(mock.isConnected)
    }

    func test_networkMonitor_startsAsConnected() {
        let monitor = NetworkMonitor()
        XCTAssertTrue(monitor.isConnected)
    }

    func test_networkMonitor_startAndDeinitDoesNotCrash() {
        // Verify the init/deinit lifecycle completes without crash
        var monitor: NetworkMonitor? = NetworkMonitor()
        XCTAssertNotNil(monitor)
        monitor = nil
    }
}
