import Foundation

public enum ErrorCode: String, Codable, Sendable {
    case micPermissionDenied
    case sessionAlreadyActive
    case invalidConfig
    case encoderFailed
    case uploadFailed
    case modelLoadFailed
    case networkUnavailable
    case dbError
    case invalidStateTransition
    case initTransactionFailed
    case stopTransactionFailed
    case commitTransactionFailed
    case pollTimeout
    case transcriptionFailed
    case recorderSetupFailed
    case retryExhausted
    case txnLimitReached
    case unknown
}
