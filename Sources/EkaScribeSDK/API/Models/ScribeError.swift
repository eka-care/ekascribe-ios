import Foundation

public struct ScribeError: Error, Sendable {
    public let code: ErrorCode
    public let message: String
    public var isRecoverable: Bool

    public init(code: ErrorCode, message: String, isRecoverable: Bool = false) {
        self.code = code
        self.message = message
        self.isRecoverable = isRecoverable
    }
}
