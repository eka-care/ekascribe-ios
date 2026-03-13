import XCTest
@testable import EkaScribeSDK

final class TransactionManagerFullTests: XCTestCase {
    private var apiService: MockScribeAPIService!
    private var dataManager: MockDataManager!
    private var uploader: MockChunkUploader!
    private var logger: MockLogger!
    private var sut: TransactionManager!

    override func setUp() {
        super.setUp()
        apiService = MockScribeAPIService()
        dataManager = MockDataManager()
        uploader = MockChunkUploader()
        logger = MockLogger()
        sut = TransactionManager(
            apiService: apiService,
            dataManager: dataManager,
            chunkUploader: uploader,
            bucketName: "test-bucket",
            maxUploadRetries: 2,
            pollMaxRetries: 3,
            pollDelayMs: 10,
            logger: logger
        )
    }

    private func saveSession(_ sessionId: String, stage: String = TransactionStage.initialize.rawValue, folderName: String = "240101", bid: String = "bid-1") {
        dataManager.sessions[sessionId] = SessionRecord(
            sessionId: sessionId,
            createdAt: 1000,
            updatedAt: 1000,
            state: SessionState.recording.rawValue,
            chunkCount: 0,
            uploadStage: stage,
            folderName: folderName,
            bid: bid
        )
    }

    private func saveChunk(_ chunkId: String, sessionId: String, index: Int, state: String = UploadState.success.rawValue, filePath: String = "/tmp/test.m4a") {
        dataManager.chunks[chunkId] = AudioChunkRecord(
            chunkId: chunkId,
            sessionId: sessionId,
            chunkIndex: index,
            filePath: filePath,
            fileName: "\(index + 1).m4a",
            startTimeMs: index * 10000,
            endTimeMs: (index + 1) * 10000,
            durationMs: 10000,
            uploadState: state,
            retryCount: 0,
            createdAt: 1000
        )
    }

    // MARK: - initTransaction

    func testInitTransactionSuccess() async {
        saveSession("s1")
        apiService.initResult = .success(
            InitTransactionResponse(bId: "bid-123", message: nil, status: nil, txnId: nil, error: nil),
            statusCode: 200
        )

        let result = await sut.initTransaction(sessionId: "s1", sessionConfig: SessionConfig(languages: ["en-IN"], mode: "dictation", modelType: "pro"), folderName: "240101")

        if case .success(_, let bid) = result {
            XCTAssertEqual(bid, "bid-123")
        } else {
            XCTFail("Expected success")
        }
        XCTAssertEqual(apiService.initCallCount, 1)
        XCTAssertEqual(dataManager.sessions["s1"]?.uploadStage, TransactionStage.stop.rawValue)
    }

    func testInitTransactionServerError() async {
        let result = await sut.initTransaction(
            sessionId: "s1",
            sessionConfig: SessionConfig(languages: ["en-IN"], mode: "dictation", modelType: "pro"),
            folderName: "240101"
        )

        apiService.initResult = .serverError(statusCode: 500, message: "Internal error")
        let errorResult = await sut.initTransaction(sessionId: "s1", sessionConfig: SessionConfig(languages: ["en-IN"], mode: "dictation", modelType: "pro"), folderName: "240101")

        if case .error(let msg) = errorResult {
            XCTAssertEqual(msg, "Internal error")
        } else {
            XCTFail("Expected error, got \(errorResult)")
        }
        _ = result
    }

    func testInitTransactionNetworkError() async {
        apiService.initResult = .networkError(NSError(domain: "net", code: -1))

        let result = await sut.initTransaction(sessionId: "s1", sessionConfig: SessionConfig(languages: ["en-IN"], mode: "dictation", modelType: "pro"), folderName: "240101")

        if case .error(let msg) = result {
            XCTAssertTrue(msg.hasPrefix("Network error:"))
        } else {
            XCTFail("Expected error")
        }
    }

    // MARK: - stopTransaction

    func testStopTransactionSuccess() async {
        saveSession("s1", stage: TransactionStage.stop.rawValue)
        saveChunk("c1", sessionId: "s1", index: 0)

        let result = await sut.stopTransaction(sessionId: "s1")

        if case .success = result {
            XCTAssertEqual(dataManager.sessions["s1"]?.uploadStage, TransactionStage.commit.rawValue)
        } else {
            XCTFail("Expected success")
        }
    }

    func testStopTransactionError() async {
        apiService.stopResult = .serverError(statusCode: 500, message: "stop failed")

        let result = await sut.stopTransaction(sessionId: "s1")

        if case .error(let msg) = result {
            XCTAssertEqual(msg, "stop failed")
        } else {
            XCTFail("Expected error")
        }
    }

    // MARK: - commitTransaction

    func testCommitTransactionSuccess() async {
        saveSession("s1", stage: TransactionStage.commit.rawValue)
        saveChunk("c1", sessionId: "s1", index: 0)

        let result = await sut.commitTransaction(sessionId: "s1")

        if case .success = result {
            XCTAssertEqual(dataManager.sessions["s1"]?.uploadStage, TransactionStage.analyzing.rawValue)
        } else {
            XCTFail("Expected success")
        }
    }

    func testCommitTransactionError() async {
        apiService.commitResult = .serverError(statusCode: 500, message: "commit failed")

        let result = await sut.commitTransaction(sessionId: "s1")

        if case .error(let msg) = result {
            XCTAssertEqual(msg, "commit failed")
        } else {
            XCTFail("Expected error")
        }
    }

    // MARK: - pollResult

    private func decodeResponse(_ json: String) -> ScribeResultResponse {
        try! JSONDecoder().decode(ScribeResultResponse.self, from: Data(json.utf8))
    }

    func testPollResultImmediateSuccess() async {
        saveSession("s1", stage: TransactionStage.analyzing.rawValue)
        let successResponse = decodeResponse("""
        { "data": { "output": [{ "name": "test", "status": "success" }] } }
        """)
        apiService.getResultResult = .success(successResponse, statusCode: 200)

        let result = await sut.pollResult(sessionId: "s1")

        if case .success = result {
            XCTAssertEqual(dataManager.sessions["s1"]?.uploadStage, TransactionStage.completed.rawValue)
        } else {
            XCTFail("Expected success, got \(result)")
        }
    }

    func testPollResultAllFailure() async {
        saveSession("s1", stage: TransactionStage.analyzing.rawValue)
        let failureResponse = decodeResponse("""
        { "data": { "output": [{ "name": "test", "status": "failure" }] } }
        """)
        apiService.getResultResult = .success(failureResponse, statusCode: 200)

        let result = await sut.pollResult(sessionId: "s1")

        if case .failed(let error) = result {
            XCTAssertTrue(error.contains("failed"))
            XCTAssertEqual(dataManager.sessions["s1"]?.uploadStage, TransactionStage.failure.rawValue)
        } else {
            XCTFail("Expected failed, got \(result)")
        }
    }

    func testPollResultTimeout() async {
        // API always returns 202 (in progress)
        apiService.getResultResult = .success(ScribeResultResponse(data: nil), statusCode: 202)

        let result = await sut.pollResult(sessionId: "s1")

        if case .timeout = result {
            // Expected
        } else {
            XCTFail("Expected timeout, got \(result)")
        }
        // Should have retried pollMaxRetries (3) times
        XCTAssertEqual(apiService.getResultCallCount, 3)
    }

    func testPollResult202ThenSuccess() async {
        saveSession("s1", stage: TransactionStage.analyzing.rawValue)
        var callCount = 0
        let successResponse = decodeResponse("""
        { "data": { "output": [{ "name": "t", "status": "success" }] } }
        """)

        // We need to return 202 first, then 200 with success
        // Since MockScribeAPIService returns the same result each time,
        // we'll use a custom approach
        let mockAPI = SequentialMockAPI()
        mockAPI.results = [
            .success(ScribeResultResponse(data: nil), statusCode: 202),
            .success(successResponse, statusCode: 200)
        ]

        let txnManager = TransactionManager(
            apiService: mockAPI,
            dataManager: dataManager,
            chunkUploader: uploader,
            bucketName: "test",
            maxUploadRetries: 2,
            pollMaxRetries: 5,
            pollDelayMs: 10,
            logger: logger
        )

        let result = await txnManager.pollResult(sessionId: "s1")

        if case .success = result {
            // Expected
        } else {
            XCTFail("Expected success, got \(result)")
        }
        _ = callCount
    }

    func testPollResultServerErrorRetries() async {
        apiService.getResultResult = .serverError(statusCode: 500, message: "error")

        let result = await sut.pollResult(sessionId: "s1")

        // Should timeout after retrying
        if case .timeout = result {
            // Expected
        } else {
            XCTFail("Expected timeout after server errors")
        }
        XCTAssertEqual(apiService.getResultCallCount, 3)
    }

    // MARK: - retryFailedUploads

    func testRetryAllUploaded() async {
        saveSession("s1")
        saveChunk("c1", sessionId: "s1", index: 0, state: UploadState.success.rawValue)
        saveChunk("c2", sessionId: "s1", index: 1, state: UploadState.success.rawValue)

        let result = await sut.retryFailedUploads(sessionId: "s1")

        XCTAssertTrue(result)
        XCTAssertEqual(uploader.uploadCallCount, 0)
        XCTAssertTrue(uploader.clearCacheCalled)
    }

    func testRetrySuccessfulRetry() async {
        saveSession("s1")
        // Create a real temp file for the chunk
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let tempFile = outputDir.appendingPathComponent("chunk.m4a")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0x01]))
        saveChunk("c1", sessionId: "s1", index: 0, state: UploadState.failed.rawValue, filePath: tempFile.path)
        uploader.uploadResult = .success(url: "s3://bucket/file.m4a")

        let result = await sut.retryFailedUploads(sessionId: "s1")

        XCTAssertTrue(result)
        XCTAssertEqual(dataManager.chunks["c1"]?.uploadState, UploadState.success.rawValue)
    }

    private var outputDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TxnTests")
    }

    func testRetryUploadFails() async {
        saveSession("s1")
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("retry_fail_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0x01]))
        saveChunk("c1", sessionId: "s1", index: 0, state: UploadState.failed.rawValue, filePath: tempFile.path)
        uploader.uploadResult = .failure(error: "upload error", isRetryable: true)

        let result = await sut.retryFailedUploads(sessionId: "s1")

        XCTAssertFalse(result)
        XCTAssertEqual(dataManager.chunks["c1"]?.uploadState, UploadState.failed.rawValue)
        try? FileManager.default.removeItem(at: tempFile)
    }

    func testRetryMissingFile() async {
        saveSession("s1")
        saveChunk("c1", sessionId: "s1", index: 0, state: UploadState.failed.rawValue, filePath: "/nonexistent/file.m4a")

        let result = await sut.retryFailedUploads(sessionId: "s1")

        // Missing files are skipped, so areAllChunksUploaded returns false
        XCTAssertFalse(result)
        // Logger should have warned
        XCTAssertTrue(logger.entries.contains { $0.message.contains("missing") })
    }

    func testRetryClearsCacheFirst() async {
        saveSession("s1")
        saveChunk("c1", sessionId: "s1", index: 0)

        _ = await sut.retryFailedUploads(sessionId: "s1")

        XCTAssertTrue(uploader.clearCacheCalled)
    }

    // MARK: - checkAndProgress

    func testCheckAndProgressFromInit() async {
        saveSession("s1", stage: TransactionStage.initialize.rawValue)
        apiService.initResult = .success(
            InitTransactionResponse(bId: "bid-1", message: nil, status: nil, txnId: nil, error: nil),
            statusCode: 200
        )
        // After init succeeds, it recurses to STOP stage -> needs retryFailedUploads + stopTransaction
        // which needs chunks to be uploaded and stopTransaction to succeed
        // For simplicity, just check that initTransaction is called
        let result = await sut.checkAndProgress(sessionId: "s1", sessionConfig: SessionConfig(languages: ["en-IN"], mode: "dictation", modelType: "pro"))

        XCTAssertEqual(apiService.initCallCount, 1)
        // Result depends on recursion but init was called
        _ = result
    }

    func testCheckAndProgressCompleted() async {
        saveSession("s1", stage: TransactionStage.completed.rawValue)

        let result = await sut.checkAndProgress(sessionId: "s1")

        if case .success = result {
            // Expected
        } else {
            XCTFail("Expected success for completed stage")
        }
    }

    func testCheckAndProgressSessionNotFound() async {
        let result = await sut.checkAndProgress(sessionId: "nonexistent")

        if case .error(let msg) = result {
            XCTAssertEqual(msg, "Session not found")
        } else {
            XCTFail("Expected error")
        }
    }

    func testCheckAndProgressFromCommit() async {
        saveSession("s1", stage: TransactionStage.commit.rawValue)
        apiService.commitResult = .success(StopTransactionResponse(message: nil, status: nil, error: nil), statusCode: 200)

        let result = await sut.checkAndProgress(sessionId: "s1")

        XCTAssertEqual(apiService.commitCallCount, 1)
        _ = result
    }

    func testCheckAndProgressNoConfigForInit() async {
        saveSession("s1", stage: TransactionStage.initialize.rawValue)

        let result = await sut.checkAndProgress(sessionId: "s1", sessionConfig: nil)

        if case .error(let msg) = result {
            XCTAssertTrue(msg.contains("config"))
        } else {
            XCTFail("Expected error when no config provided for init stage")
        }
    }
}

// MARK: - Sequential Mock API for multi-call tests

private final class SequentialMockAPI: ScribeAPIServiceProtocol {
    var results: [NetworkResult<ScribeResultResponse>] = []
    private var callIndex = 0

    func initTransaction(_ sessionId: String, _ request: InitTransactionRequest) async -> NetworkResult<InitTransactionResponse> {
        .success(InitTransactionResponse(bId: "bid", message: nil, status: nil, txnId: nil, error: nil), statusCode: 200)
    }

    func stopTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse> {
        .success(StopTransactionResponse(message: nil, status: nil, error: nil), statusCode: 200)
    }

    func commitTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse> {
        .success(StopTransactionResponse(message: nil, status: nil, error: nil), statusCode: 200)
    }

    func getTransactionResult(_ sessionId: String) async -> NetworkResult<ScribeResultResponse> {
        let result = callIndex < results.count ? results[callIndex] : results.last!
        callIndex += 1
        return result
    }
}
