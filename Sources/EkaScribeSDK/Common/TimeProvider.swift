import Foundation

protocol TimeProvider {
    func nowMillis() -> Int64
}

struct DefaultTimeProvider: TimeProvider {
    func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
