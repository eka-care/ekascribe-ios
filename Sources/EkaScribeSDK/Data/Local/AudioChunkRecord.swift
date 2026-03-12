import Foundation
import GRDB

struct AudioChunkRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "scribe_audio_chunk"

    var chunkId: String
    var sessionId: String
    var chunkIndex: Int
    var filePath: String
    var fileName: String
    var startTimeMs: Int64
    var endTimeMs: Int64
    var durationMs: Int64
    var uploadState: String = "PENDING"
    var retryCount: Int = 0
    var qualityScore: Float?
    var createdAt: Int64
}

enum UploadState: String {
    case pending = "PENDING"
    case inProgress = "IN_PROGRESS"
    case success = "SUCCESS"
    case failed = "FAILED"
}

enum TransactionStage: String {
    case initialize = "INIT"
    case stop = "STOP"
    case commit = "COMMIT"
    case analyzing = "ANALYZING"
    case completed = "COMPLETED"
    case failure = "FAILURE"
    case error = "ERROR"
}
