import Combine
import Foundation
import GRDB

final class DefaultDataManager: DataManager {
    private let database: ScribeDatabase
    private let timeProvider: TimeProvider
    private let logger: Logger

    init(database: ScribeDatabase, timeProvider: TimeProvider, logger: Logger) {
        self.database = database
        self.timeProvider = timeProvider
        self.logger = logger
    }

    func saveSession(_ session: SessionRecord) async throws {
        var mutableSession = session
        mutableSession.updatedAt = timeProvider.nowMillis()
        let updated = mutableSession

        try await database.dbPool.write { db in
            var record = updated
            try record.save(db)
        }
    }

    func getSession(_ sessionId: String) async throws -> SessionRecord? {
        try await database.dbPool.read { db in
            try SessionRecord.fetchOne(db, key: sessionId)
        }
    }

    func getAllSessions() async throws -> [SessionRecord] {
        try await database.dbPool.read { db in
            try SessionRecord
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func deleteSession(_ sessionId: String) async throws {
        _ = try await database.dbPool.write { db in
            try SessionRecord.deleteOne(db, key: sessionId)
        }
    }

    func updateSessionState(_ sessionId: String, _ state: String) async throws {
        let now = timeProvider.nowMillis()
        try await database.dbPool.write { db in
            try db.execute(
                sql: "UPDATE scribe_session SET state = ?, updatedAt = ? WHERE sessionId = ?",
                arguments: [state, now, sessionId]
            )
        }
    }

    func updateUploadStage(_ sessionId: String, _ stage: String) async throws {
        let now = timeProvider.nowMillis()
        try await database.dbPool.write { db in
            try db.execute(
                sql: "UPDATE scribe_session SET uploadStage = ?, updatedAt = ? WHERE sessionId = ?",
                arguments: [stage, now, sessionId]
            )
        }
    }

    func updateSessionMetadata(_ sessionId: String, _ metadata: String) async throws {
        let now = timeProvider.nowMillis()
        try await database.dbPool.write { db in
            try db.execute(
                sql: "UPDATE scribe_session SET sessionMetadata = ?, updatedAt = ? WHERE sessionId = ?",
                arguments: [metadata, now, sessionId]
            )
        }
    }

    func updateStageAndBid(_ sessionId: String, _ stage: String, _ bid: String) async throws {
        let now = timeProvider.nowMillis()
        try await database.dbPool.write { db in
            try db.execute(
                sql: "UPDATE scribe_session SET uploadStage = ?, bid = ?, updatedAt = ? WHERE sessionId = ?",
                arguments: [stage, bid, now, sessionId]
            )
        }
    }

    func updateFolderAndBid(_ sessionId: String, _ folderName: String, _ bid: String) async throws {
        let now = timeProvider.nowMillis()
        try await database.dbPool.write { db in
            try db.execute(
                sql: "UPDATE scribe_session SET folderName = ?, bid = ?, updatedAt = ? WHERE sessionId = ?",
                arguments: [folderName, bid, now, sessionId]
            )
        }
    }

    func getSessionsByStage(_ stage: String) async throws -> [SessionRecord] {
        try await database.dbPool.read { db in
            try SessionRecord
                .filter(Column("uploadStage") == stage)
                .fetchAll(db)
        }
    }

    func saveChunk(_ chunk: AudioChunkRecord) async throws {
        var mutableChunk = chunk
        mutableChunk.createdAt = max(0, chunk.createdAt)
        let updated = mutableChunk
        let sessionId = updated.sessionId
        let now = timeProvider.nowMillis()

        try await database.dbPool.write { db in
            var record = updated
            try record.save(db)
            try db.execute(
                sql: "UPDATE scribe_session SET chunkCount = chunkCount + 1, updatedAt = ? WHERE sessionId = ?",
                arguments: [now, sessionId]
            )
        }
    }

    func getAllChunks(sessionId: String) async throws -> [AudioChunkRecord] {
        try await database.dbPool.read { db in
            try AudioChunkRecord
                .filter(Column("sessionId") == sessionId)
                .order(Column("chunkIndex").asc)
                .fetchAll(db)
        }
    }

    func getUploadedChunks(sessionId: String) async throws -> [AudioChunkRecord] {
        try await database.dbPool.read { db in
            try AudioChunkRecord
                .filter(Column("sessionId") == sessionId && Column("uploadState") == UploadState.success.rawValue)
                .order(Column("chunkIndex").asc)
                .fetchAll(db)
        }
    }

    func getChunkCount(sessionId: String) async throws -> Int {
        try await database.dbPool.read { db in
            try AudioChunkRecord
                .filter(Column("sessionId") == sessionId)
                .fetchCount(db)
        }
    }

    func markInProgress(_ chunkId: String) async throws {
        try await setChunkState(chunkId: chunkId, state: UploadState.inProgress.rawValue)
    }

    func markUploaded(_ chunkId: String) async throws {
        try await setChunkState(chunkId: chunkId, state: UploadState.success.rawValue)
    }

    func markFailed(_ chunkId: String) async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: "UPDATE scribe_audio_chunk SET uploadState = ?, retryCount = retryCount + 1 WHERE chunkId = ?",
                arguments: [UploadState.failed.rawValue, chunkId]
            )
        }
    }

    func areAllChunksUploaded(sessionId: String) async throws -> Bool {
        try await database.dbPool.read { db in
            let total = try AudioChunkRecord
                .filter(Column("sessionId") == sessionId)
                .fetchCount(db)
            guard total > 0 else { return true }
            let uploaded = try AudioChunkRecord
                .filter(Column("sessionId") == sessionId && Column("uploadState") == UploadState.success.rawValue)
                .fetchCount(db)
            return total == uploaded
        }
    }

    func observeSession(_ sessionId: String) -> AnyPublisher<SessionRecord?, Never> {
        ValueObservation
            .tracking { db in
                try? SessionRecord.fetchOne(db, key: sessionId)
            }
            .publisher(in: database.dbPool)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.logger.error("Data", "Session observation failed", error)
                }
            })
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }

    private func setChunkState(chunkId: String, state: String) async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: "UPDATE scribe_audio_chunk SET uploadState = ? WHERE chunkId = ?",
                arguments: [state, chunkId]
            )
        }
    }
}
