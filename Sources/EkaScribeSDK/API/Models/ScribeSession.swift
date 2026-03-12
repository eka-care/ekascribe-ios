import Foundation

public struct ScribeSession: Sendable {
    public let sessionId: String
    public let createdAt: Int64
    public let updatedAt: Int64
    public let state: String
    public let chunkCount: Int
    public let uploadStage: UploadStage

    public init(sessionId: String, createdAt: Int64, updatedAt: Int64, state: String, chunkCount: Int, uploadStage: UploadStage) {
        self.sessionId = sessionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
        self.chunkCount = chunkCount
        self.uploadStage = uploadStage
    }
}
