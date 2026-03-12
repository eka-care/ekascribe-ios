import Foundation
import os

final class DefaultLogger: Logger {
    private let osLog = os.Logger(subsystem: "com.eka.scribesdk", category: "ScribeSDK")

    func debug(_ tag: String, _ message: String) {
        osLog.debug("[\(tag, privacy: .public)] \(message, privacy: .public)")
    }

    func info(_ tag: String, _ message: String) {
        osLog.info("[\(tag, privacy: .public)] \(message, privacy: .public)")
    }

    func warn(_ tag: String, _ message: String, _ error: Error?) {
        let suffix = error?.localizedDescription ?? ""
        osLog.warning("[\(tag, privacy: .public)] \(message, privacy: .public) \(suffix, privacy: .public)")
    }

    func error(_ tag: String, _ message: String, _ error: Error?) {
        let suffix = error?.localizedDescription ?? ""
        osLog.error("[\(tag, privacy: .public)] \(message, privacy: .public) \(suffix, privacy: .public)")
    }
}
