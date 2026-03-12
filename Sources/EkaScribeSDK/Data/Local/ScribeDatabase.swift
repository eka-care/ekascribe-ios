import Foundation
import GRDB

final class ScribeDatabase {
    let dbPool: DatabasePool

    init(path: String) throws {
        dbPool = try DatabasePool(path: path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = true

        migrator.registerMigration("v1") { db in
            try db.create(table: "scribe_session") { t in
                t.primaryKey("sessionId", .text)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("state", .text).notNull()
                t.column("chunkCount", .integer).notNull().defaults(to: 0)
                t.column("mode", .text)
                t.column("ownerId", .text)
                t.column("metadata", .text)
                t.column("uploadStage", .text).notNull().defaults(to: "INIT")
                t.column("sessionMetadata", .text)
                t.column("folderName", .text)
                t.column("bid", .text)
            }

            try db.create(table: "scribe_audio_chunk") { t in
                t.primaryKey("chunkId", .text)
                t.column("sessionId", .text).notNull()
                    .references("scribe_session", column: "sessionId", onDelete: .cascade)
                t.column("chunkIndex", .integer).notNull()
                t.column("filePath", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("startTimeMs", .integer).notNull()
                t.column("endTimeMs", .integer).notNull()
                t.column("durationMs", .integer).notNull()
                t.column("uploadState", .text).notNull().defaults(to: "PENDING")
                t.column("retryCount", .integer).notNull().defaults(to: 0)
                t.column("qualityScore", .double)
                t.column("createdAt", .integer).notNull()
            }

            try db.create(index: "idx_chunk_session", on: "scribe_audio_chunk", columns: ["sessionId"])
        }

        try migrator.migrate(dbPool)
    }
}
