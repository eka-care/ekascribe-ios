import Foundation

enum IdGenerator {
    static func sessionId() -> String { "i-\(UUID().uuidString.lowercased())" }
    static func chunkId(sessionId: String, index: Int) -> String { "\(sessionId)_\(index)" }
}
