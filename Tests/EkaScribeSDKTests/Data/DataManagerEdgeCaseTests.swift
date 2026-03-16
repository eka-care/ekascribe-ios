import Combine
import XCTest
@testable import EkaScribeSDK

final class DataManagerEdgeCaseTests: XCTestCase {
    private var database: ScribeDatabase!
    private var timeProvider: MockTimeProvider!
    private var logger: MockLogger!
    private var sut: DefaultDataManager!
    private var dbPath: String!

    override func setUp() {
        super.setUp()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dm_edge_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        dbPath = tmpDir.appendingPathComponent("test.sqlite").path

        database = try! ScribeDatabase(path: dbPath)
        timeProvider = MockTimeProvider()
        logger = MockLogger()
        sut = DefaultDataManager(database: database, timeProvider: timeProvider, logger: logger)
    }

    override func tearDown() {
        sut = nil
        database = nil
        if let dbPath {
            try? FileManager.default.removeItem(atPath: dbPath)
            let dir = (dbPath as NSString).deletingLastPathComponent
            try? FileManager.default.removeItem(atPath: dir)
        }
        super.tearDown()
    }

    private func makeSession(_ id: String, updatedAt: Int = 1000) -> SessionRecord {
        SessionRecord(
            sessionId: id,
            createdAt: 1000,
            updatedAt: updatedAt,
            state: SessionState.idle.rawValue,
            chunkCount: 0,
            uploadStage: TransactionStage.initialize.rawValue
        )
    }

    private func makeChunk(_ id: String, sessionId: String, index: Int) -> AudioChunkRecord {
        AudioChunkRecord(
            chunkId: id,
            sessionId: sessionId,
            chunkIndex: index,
            filePath: "/tmp/\(id).m4a",
            fileName: "\(index).m4a",
            startTimeMs: index * 10000,
            endTimeMs: (index + 1) * 10000,
            durationMs: 10000,
            createdAt: 1000
        )
    }

    // MARK: - Session Edge Cases

    func testGetChunkCountForEmptySession() async throws {
        try await sut.saveSession(makeSession("s1"))
        let count = try await sut.getChunkCount(sessionId: "s1")
        XCTAssertEqual(count, 0)
    }

    func testGetSessionsByStageEmpty() async throws {
        try await sut.saveSession(makeSession("s1"))
        let results = try await sut.getSessionsByStage(TransactionStage.commit.rawValue)
        XCTAssertTrue(results.isEmpty)
    }

    func testMultipleSessionsOrdering() async throws {
        timeProvider.currentTime = 1000
        try await sut.saveSession(makeSession("s1", updatedAt: 1000))
        timeProvider.currentTime = 3000
        try await sut.saveSession(makeSession("s2", updatedAt: 3000))
        timeProvider.currentTime = 2000
        try await sut.saveSession(makeSession("s3", updatedAt: 2000))

        let all = try await sut.getAllSessions()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].sessionId, "s2")
        XCTAssertEqual(all[1].sessionId, "s3")
        XCTAssertEqual(all[2].sessionId, "s1")
    }

    func testSaveChunkIncrementsCountMultipleTimes() async throws {
        try await sut.saveSession(makeSession("s1"))
        try await sut.saveChunk(makeChunk("c1", sessionId: "s1", index: 0))
        try await sut.saveChunk(makeChunk("c2", sessionId: "s1", index: 1))
        try await sut.saveChunk(makeChunk("c3", sessionId: "s1", index: 2))

        let session = try await sut.getSession("s1")
        XCTAssertEqual(session?.chunkCount, 3)
    }

    // MARK: - Chunk Edge Cases

    func testGetAllChunksReturnsOrderedByIndex() async throws {
        try await sut.saveSession(makeSession("s1"))
        try await sut.saveChunk(makeChunk("c3", sessionId: "s1", index: 2))
        try await sut.saveChunk(makeChunk("c1", sessionId: "s1", index: 0))
        try await sut.saveChunk(makeChunk("c2", sessionId: "s1", index: 1))

        let chunks = try await sut.getAllChunks(sessionId: "s1")
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].chunkIndex, 0)
        XCTAssertEqual(chunks[1].chunkIndex, 1)
        XCTAssertEqual(chunks[2].chunkIndex, 2)
    }

    func testAreAllChunksUploadedMixedStates() async throws {
        try await sut.saveSession(makeSession("s1"))
        try await sut.saveChunk(makeChunk("c1", sessionId: "s1", index: 0))
        try await sut.saveChunk(makeChunk("c2", sessionId: "s1", index: 1))

        try await sut.markUploaded("c1")
        // c2 stays PENDING

        let result = try await sut.areAllChunksUploaded(sessionId: "s1")
        XCTAssertFalse(result)
    }

    func testAreAllChunksUploadedAllSuccess() async throws {
        try await sut.saveSession(makeSession("s1"))
        try await sut.saveChunk(makeChunk("c1", sessionId: "s1", index: 0))
        try await sut.saveChunk(makeChunk("c2", sessionId: "s1", index: 1))

        try await sut.markUploaded("c1")
        try await sut.markUploaded("c2")

        let result = try await sut.areAllChunksUploaded(sessionId: "s1")
        XCTAssertTrue(result)
    }

    func testMarkFailedIncrementsRetryCount() async throws {
        try await sut.saveSession(makeSession("s1"))
        try await sut.saveChunk(makeChunk("c1", sessionId: "s1", index: 0))

        try await sut.markFailed("c1")
        try await sut.markFailed("c1")

        let chunks = try await sut.getAllChunks(sessionId: "s1")
        XCTAssertEqual(chunks[0].retryCount, 2)
        XCTAssertEqual(chunks[0].uploadState, UploadState.failed.rawValue)
    }

    func testUpdateSessionStateWorks() async throws {
        try await sut.saveSession(makeSession("s1"))
        try await sut.updateSessionState("s1", SessionState.recording.rawValue)

        let session = try await sut.getSession("s1")
        XCTAssertEqual(session?.state, SessionState.recording.rawValue)
    }

    func testDeleteSessionRemovesChunks() async throws {
        try await sut.saveSession(makeSession("s1"))
        try await sut.saveChunk(makeChunk("c1", sessionId: "s1", index: 0))

        try await sut.deleteSession("s1")

        let session = try await sut.getSession("s1")
        XCTAssertNil(session)

        let chunks = try await sut.getAllChunks(sessionId: "s1")
        XCTAssertTrue(chunks.isEmpty)
    }
}
