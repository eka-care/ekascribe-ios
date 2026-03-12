import Combine
import Foundation

protocol DataManager {
    func saveSession(_ session: SessionRecord) async throws
    func getSession(_ sessionId: String) async throws -> SessionRecord?
    func getAllSessions() async throws -> [SessionRecord]
    func deleteSession(_ sessionId: String) async throws
    func updateSessionState(_ sessionId: String, _ state: String) async throws
    func updateUploadStage(_ sessionId: String, _ stage: String) async throws
    func updateSessionMetadata(_ sessionId: String, _ metadata: String) async throws
    func updateStageAndBid(_ sessionId: String, _ stage: String, _ bid: String) async throws
    func updateFolderAndBid(_ sessionId: String, _ folderName: String, _ bid: String) async throws
    func getSessionsByStage(_ stage: String) async throws -> [SessionRecord]

    func saveChunk(_ chunk: AudioChunkRecord) async throws
    func getAllChunks(sessionId: String) async throws -> [AudioChunkRecord]
    func getUploadedChunks(sessionId: String) async throws -> [AudioChunkRecord]
    func getChunkCount(sessionId: String) async throws -> Int
    func markInProgress(_ chunkId: String) async throws
    func markUploaded(_ chunkId: String) async throws
    func markFailed(_ chunkId: String) async throws
    func areAllChunksUploaded(sessionId: String) async throws -> Bool

    func observeSession(_ sessionId: String) -> AnyPublisher<SessionRecord?, Never>
}
