import Foundation

public enum UploadStage: String, Codable, Sendable {
    case initialize = "INIT"
    case stop = "STOP"
    case commit = "COMMIT"
    case analyzing = "ANALYZING"
    case completed = "COMPLETED"
    case failure = "FAILURE"
    case error = "ERROR"
    case cancelled = "CANCELLED"
}
