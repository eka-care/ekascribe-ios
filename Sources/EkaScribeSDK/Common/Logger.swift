import Foundation

protocol Logger: Sendable {
    func debug(_ tag: String, _ message: String)
    func info(_ tag: String, _ message: String)
    func warn(_ tag: String, _ message: String, _ error: Error?)
    func error(_ tag: String, _ message: String, _ error: Error?)
}

extension Logger {
    func warn(_ tag: String, _ message: String) { warn(tag, message, nil) }
    func error(_ tag: String, _ message: String) { error(tag, message, nil) }
}
