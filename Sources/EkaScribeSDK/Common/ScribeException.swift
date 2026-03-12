import Foundation

struct ScribeException: Error {
    let code: ErrorCode
    let message: String
    let cause: Error?

    init(code: ErrorCode, message: String, cause: Error? = nil) {
        self.code = code
        self.message = message
        self.cause = cause
    }
}
