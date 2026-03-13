import Foundation

public struct ScribeSession: Sendable {
    public let sessionId: String
    public let createdAt: Int
    public let updatedAt: Int
    public let state: String
    public let chunkCount: Int
    public let uploadStage: UploadStage

    public init(sessionId: String, createdAt: Int, updatedAt: Int, state: String, chunkCount: Int, uploadStage: UploadStage) {
        self.sessionId = sessionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
        self.chunkCount = chunkCount
        self.uploadStage = uploadStage
    }
}
