import XCTest
import GRDB
@testable import EkaScribeSDK

final class DefaultDataManagerTests: XCTestCase {
    private var dbPath: String!
    private var database: ScribeDatabase!
    private var dataManager: DefaultDataManager!
    private var timeProvider: MockTimeProvider!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataManagerTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbPath = tempDir.appendingPathComponent("test.sqlite").path
        database = try! ScribeDatabase(path: dbPath)
        timeProvider = MockTimeProvider()
        dataManager = DefaultDataManager(database: database, timeProvider: timeProvider, logger: MockLogger())
    }

    override func tearDown() {
        let dir = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeSession(id: String = "session-1", state: String = "idle", stage: String = "INIT") -> SessionRecord {
        SessionRecord(
            sessionId: id,
            createdAt: 1000,
            updatedAt: 2000,
            state: state,
            chunkCount: 0,
            mode: "dictation",
            uploadStage: stage,
            folderName: "240101",
            bid: "bid-1"
        )
    }

    private func makeChunk(chunkId: String, sessionId: String = "session-1", index: Int = 0) -> AudioChunkRecord {
        AudioChunkRecord(
            chunkId: chunkId,
            sessionId: sessionId,
            chunkIndex: index,
            filePath: "/tmp/\(chunkId).m4a",
            fileName: "\(index + 1).m4a",
            startTimeMs: index * 10000,
            endTimeMs: (index + 1) * 10000,
            durationMs: 10000,
            createdAt: 1000
        )
    }

    // MARK: - Session CRUD

    func testSaveAndGetSession() async throws {
        let session = makeSession()
        try await dataManager.saveSession(session)

        let fetched = try await dataManager.getSession("session-1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.sessionId, "session-1")
        XCTAssertEqual(fetched?.state, "idle")
    }

    func testGetSessionReturnsNilForMissing() async throws {
        let fetched = try await dataManager.getSession("nonexistent")
        XCTAssertNil(fetched)
    }

    func testGetAllSessions() async throws {
        timeProvider.currentTime = 100
        try await dataManager.saveSession(makeSession(id: "s1"))
        timeProvider.currentTime = 200
        try await dataManager.saveSession(makeSession(id: "s2"))

        let all = try await dataManager.getAllSessions()
        XCTAssertEqual(all.count, 2)
        // Ordered by updatedAt desc
        XCTAssertEqual(all[0].sessionId, "s2")
        XCTAssertEqual(all[1].sessionId, "s1")
    }

    func testDeleteSession() async throws {
        try await dataManager.saveSession(makeSession(id: "s1"))
        try await dataManager.deleteSession("s1")

        let fetched = try await dataManager.getSession("s1")
        XCTAssertNil(fetched)
    }

    // MARK: - Session Updates

    func testUpdateSessionState() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.updateSessionState("session-1", "recording")

        let fetched = try await dataManager.getSession("session-1")
        XCTAssertEqual(fetched?.state, "recording")
    }

    func testUpdateUploadStage() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.updateUploadStage("session-1", "STOP")

        let fetched = try await dataManager.getSession("session-1")
        XCTAssertEqual(fetched?.uploadStage, "STOP")
    }

    func testUpdateSessionMetadata() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.updateSessionMetadata("session-1", "{\"key\":\"value\"}")

        let fetched = try await dataManager.getSession("session-1")
        XCTAssertEqual(fetched?.sessionMetadata, "{\"key\":\"value\"}")
    }

    func testUpdateStageAndBid() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.updateStageAndBid("session-1", "COMMIT", "new-bid")

        let fetched = try await dataManager.getSession("session-1")
        XCTAssertEqual(fetched?.uploadStage, "COMMIT")
        XCTAssertEqual(fetched?.bid, "new-bid")
    }

    func testUpdateFolderAndBid() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.updateFolderAndBid("session-1", "240202", "bid-x")

        let fetched = try await dataManager.getSession("session-1")
        XCTAssertEqual(fetched?.folderName, "240202")
        XCTAssertEqual(fetched?.bid, "bid-x")
    }

    func testGetSessionsByStage() async throws {
        try await dataManager.saveSession(makeSession(id: "s1", stage: "INIT"))
        try await dataManager.saveSession(makeSession(id: "s2", stage: "STOP"))
        try await dataManager.saveSession(makeSession(id: "s3", stage: "INIT"))

        let initSessions = try await dataManager.getSessionsByStage("INIT")
        XCTAssertEqual(initSessions.count, 2)

        let stopSessions = try await dataManager.getSessionsByStage("STOP")
        XCTAssertEqual(stopSessions.count, 1)
        XCTAssertEqual(stopSessions[0].sessionId, "s2")
    }

    // MARK: - Chunk Operations

    func testSaveChunkIncrementSessionCount() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.saveChunk(makeChunk(chunkId: "c1", index: 0))

        let session = try await dataManager.getSession("session-1")
        XCTAssertEqual(session?.chunkCount, 1)

        try await dataManager.saveChunk(makeChunk(chunkId: "c2", index: 1))
        let updatedSession = try await dataManager.getSession("session-1")
        XCTAssertEqual(updatedSession?.chunkCount, 2)
    }

    func testGetAllChunksOrdered() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.saveChunk(makeChunk(chunkId: "c2", index: 2))
        try await dataManager.saveChunk(makeChunk(chunkId: "c0", index: 0))
        try await dataManager.saveChunk(makeChunk(chunkId: "c1", index: 1))

        let chunks = try await dataManager.getAllChunks(sessionId: "session-1")
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].chunkIndex, 0)
        XCTAssertEqual(chunks[1].chunkIndex, 1)
        XCTAssertEqual(chunks[2].chunkIndex, 2)
    }

    func testGetChunkCount() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.saveChunk(makeChunk(chunkId: "c1", index: 0))
        try await dataManager.saveChunk(makeChunk(chunkId: "c2", index: 1))

        let count = try await dataManager.getChunkCount(sessionId: "session-1")
        XCTAssertEqual(count, 2)
    }

    // MARK: - Chunk State

    func testMarkInProgress() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.saveChunk(makeChunk(chunkId: "c1"))
        try await dataManager.markInProgress("c1")

        let chunks = try await dataManager.getAllChunks(sessionId: "session-1")
        XCTAssertEqual(chunks[0].uploadState, "IN_PROGRESS")
    }

    func testMarkUploaded() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.saveChunk(makeChunk(chunkId: "c1"))
        try await dataManager.markUploaded("c1")

        let chunks = try await dataManager.getAllChunks(sessionId: "session-1")
        XCTAssertEqual(chunks[0].uploadState, "SUCCESS")
    }

    func testMarkFailed() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.saveChunk(makeChunk(chunkId: "c1"))
        try await dataManager.markFailed("c1")

        let chunks = try await dataManager.getAllChunks(sessionId: "session-1")
        XCTAssertEqual(chunks[0].uploadState, "FAILED")
        XCTAssertEqual(chunks[0].retryCount, 1)

        // Mark failed again increments retry count
        try await dataManager.markFailed("c1")
        let updated = try await dataManager.getAllChunks(sessionId: "session-1")
        XCTAssertEqual(updated[0].retryCount, 2)
    }

    // MARK: - Uploaded Chunks

    func testGetUploadedChunks() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.saveChunk(makeChunk(chunkId: "c1", index: 0))
        try await dataManager.saveChunk(makeChunk(chunkId: "c2", index: 1))
        try await dataManager.saveChunk(makeChunk(chunkId: "c3", index: 2))

        try await dataManager.markUploaded("c1")
        try await dataManager.markUploaded("c3")

        let uploaded = try await dataManager.getUploadedChunks(sessionId: "session-1")
        XCTAssertEqual(uploaded.count, 2)
        XCTAssertEqual(uploaded[0].chunkId, "c1")
        XCTAssertEqual(uploaded[1].chunkId, "c3")
    }

    func testAreAllChunksUploadedTrueWhenAllSuccess() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.saveChunk(makeChunk(chunkId: "c1", index: 0))
        try await dataManager.saveChunk(makeChunk(chunkId: "c2", index: 1))
        try await dataManager.markUploaded("c1")
        try await dataManager.markUploaded("c2")

        let allUploaded = try await dataManager.areAllChunksUploaded(sessionId: "session-1")
        XCTAssertTrue(allUploaded)
    }

    func testAreAllChunksUploadedFalseWhenPartial() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.saveChunk(makeChunk(chunkId: "c1", index: 0))
        try await dataManager.saveChunk(makeChunk(chunkId: "c2", index: 1))
        try await dataManager.markUploaded("c1")
        // c2 still pending

        let allUploaded = try await dataManager.areAllChunksUploaded(sessionId: "session-1")
        XCTAssertFalse(allUploaded)
    }

    func testAreAllChunksUploadedTrueWhenNoChunks() async throws {
        try await dataManager.saveSession(makeSession())
        let allUploaded = try await dataManager.areAllChunksUploaded(sessionId: "session-1")
        XCTAssertTrue(allUploaded)
    }

    // MARK: - Cascade Delete

    func testDeleteSessionCascadesChunks() async throws {
        try await dataManager.saveSession(makeSession())
        try await dataManager.saveChunk(makeChunk(chunkId: "c1", index: 0))
        try await dataManager.saveChunk(makeChunk(chunkId: "c2", index: 1))

        try await dataManager.deleteSession("session-1")

        let chunks = try await dataManager.getAllChunks(sessionId: "session-1")
        XCTAssertTrue(chunks.isEmpty, "Chunks should be deleted when session is deleted (cascade)")
    }
}
