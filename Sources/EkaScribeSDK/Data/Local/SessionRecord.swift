import Foundation
import GRDB

struct SessionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "scribe_session"

    var sessionId: String
    var createdAt: Int
    var updatedAt: Int
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
