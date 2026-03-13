import Foundation

protocol TimeProvider {
    func nowMillis() -> Int
}

struct DefaultTimeProvider: TimeProvider {
    func nowMillis() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }
}
