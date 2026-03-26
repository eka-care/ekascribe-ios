import Combine
import Foundation
import Network

/// Abstraction for network connectivity checks, enabling testability via mocking.
protocol NetworkMonitoring: Sendable {
    var isConnected: Bool { get }
}

/// Monitors device network connectivity using `NWPathMonitor`.
///
/// Starts monitoring on initialization and cancels on deinitialization.
/// Updates `isConnected` on the main thread via `@Published`.
final class NetworkMonitor: NetworkMonitoring, ObservableObject, @unchecked Sendable {
    @Published private(set) var isConnected: Bool = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue.global(qos: .background)

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
