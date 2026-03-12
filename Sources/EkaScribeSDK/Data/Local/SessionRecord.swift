import Foundation
import GRDB

struct SessionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "scribe_session"

    var sessionId: String
    var createdAt: Int64
    var updatedAt: Int64
    var state: String
    var chunkCount: Int = 0
    var mode: String?
    var ownerId: String?
    var metadata: String?
    var uploadStage: String = "INIT"
    var sessionMetadata: String?
    var folderName: String?
    var bid: String?
}
