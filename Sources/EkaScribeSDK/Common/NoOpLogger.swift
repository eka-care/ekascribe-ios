import Foundation

final class NoOpLogger: Logger {
    func debug(_ tag: String, _ message: String) {}
    func info(_ tag: String, _ message: String) {}
    func warn(_ tag: String, _ message: String, _ error: Error?) {}
    func error(_ tag: String, _ message: String, _ error: Error?) {}
}
