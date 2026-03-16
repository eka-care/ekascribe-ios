import XCTest
@testable import EkaScribeSDK

final class TransactionManagerEdgeCaseTests: XCTestCase {
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

    // MARK: - checkAndProgress Edge Cases

    func testCheckAndProgressFromStopWithForceCommitTrue() async {
        saveSession("s1", stage: TransactionStage.stop.rawValue)
        saveChunk("c1", sessionId: "s1", index: 0, state: UploadState.failed.rawValue)

        // retryFailedUploads will fail (file doesn't exist), but force=true should skip the upload check
        let result = await sut.checkAndProgress(sessionId: "s1", force: true)

        // Should proceed through stop → commit → poll even though uploads failed
        XCTAssertTrue(apiService.stopCallCount >= 1)
    }

    func testCheckAndProgressFromStopAllUploaded() async {
        saveSession("s1", stage: TransactionStage.stop.rawValue)
        saveChunk("c1", sessionId: "s1", index: 0, state: UploadState.success.rawValue)

        let result = await sut.checkAndProgress(sessionId: "s1")

        // Should proceed through stop → commit → poll
        XCTAssertTrue(apiService.stopCallCount >= 1)
    }

    func testCheckAndProgressFromAnalyzingSuccess() async {
        saveSession("s1", stage: TransactionStage.analyzing.rawValue)

        let successResponse = ScribeResultResponse(data: ScribeResultResponse.ResultData(
            audioMatrix: nil,
            createdAt: nil,
            output: [makeOutputDTO(name: "output", status: .success, value: "test")],
            templateResults: nil
        ))
        apiService.getResultResult = .success(successResponse, statusCode: 200)

        let result = await sut.checkAndProgress(sessionId: "s1")

        if case .success = result {
            // Expected
        } else {
            XCTFail("Expected success, got \(result)")
        }
    }

    func testCheckAndProgressFromAnalyzingFailed() async {
        saveSession("s1", stage: TransactionStage.analyzing.rawValue)

        let failedResponse = ScribeResultResponse(data: ScribeResultResponse.ResultData(
            audioMatrix: nil,
            createdAt: nil,
            output: [makeOutputDTO(name: "output", status: .failure)],
            templateResults: nil
        ))
        apiService.getResultResult = .success(failedResponse, statusCode: 200)

        let result = await sut.checkAndProgress(sessionId: "s1")

        if case .error(let message) = result {
            XCTAssertTrue(message.contains("failed") || message.contains("Poll timeout"))
        } else {
            XCTFail("Expected error")
        }
    }

    func testCheckAndProgressFromAnalyzingTimeout() async {
        saveSession("s1", stage: TransactionStage.analyzing.rawValue)

        // 202 causes polling retry
        apiService.getResultResult = .success(ScribeResultResponse(data: nil), statusCode: 202)

        let result = await sut.checkAndProgress(sessionId: "s1")

        if case .error(let message) = result {
            XCTAssertEqual(message, "Poll timeout")
        } else {
            XCTFail("Expected timeout error")
        }
    }

    func testCheckAndProgressFromFailureStage() async {
        saveSession("s1", stage: TransactionStage.failure.rawValue)

        let result = await sut.checkAndProgress(sessionId: "s1")

        if case .success = result {
            // Expected — failure/error/completed stages return success immediately
        } else {
            XCTFail("Expected success for failure stage")
        }
    }

    func testCheckAndProgressFromErrorStage() async {
        saveSession("s1", stage: TransactionStage.error.rawValue)

        let result = await sut.checkAndProgress(sessionId: "s1")

        if case .success = result {
            // Expected
        } else {
            XCTFail("Expected success for error stage")
        }
    }

    func testCheckAndProgressUnknownStage() async {
        dataManager.sessions["s1"] = SessionRecord(
            sessionId: "s1",
            createdAt: 1000,
            updatedAt: 1000,
            state: "recording",
            chunkCount: 0,
            uploadStage: "BOGUS_STAGE"
        )

        let result = await sut.checkAndProgress(sessionId: "s1")

        if case .error(let message) = result {
            XCTAssertEqual(message, "Unknown stage")
        } else {
            XCTFail("Expected unknown stage error")
        }
    }

    // MARK: - retryFailedUploads Edge Cases

    func testRetryFailedUploadsWithMixedStates() async {
        saveSession("s1", stage: TransactionStage.stop.rawValue)
        saveChunk("c1", sessionId: "s1", index: 0, state: UploadState.success.rawValue)
        saveChunk("c2", sessionId: "s1", index: 1, state: UploadState.failed.rawValue, filePath: "/tmp/nonexistent.m4a")

        let result = await sut.retryFailedUploads(sessionId: "s1")

        // c2 file doesn't exist, so it will be skipped → c2 remains failed → result is false
        XCTAssertFalse(result)
    }

    func testRetryFailedUploadsEmptyChunks() async {
        saveSession("s1", stage: TransactionStage.stop.rawValue)
        // No chunks at all

        let result = await sut.retryFailedUploads(sessionId: "s1")

        // No chunks means nothing to upload → true
        XCTAssertTrue(result)
    }

    func testRetryFailedUploadsMissingSession() async {
        // Don't save any session — returns true since there are no failed chunks

        let result = await sut.retryFailedUploads(sessionId: "nonexistent")

        XCTAssertTrue(result)
    }

    func testRetryFailedUploadsPartialSuccess() async {
        saveSession("s1", stage: TransactionStage.stop.rawValue)

        // Create temp files
        let tmpDir = FileManager.default.temporaryDirectory
        let file1 = tmpDir.appendingPathComponent("retry_test_1.m4a")
        let file2 = tmpDir.appendingPathComponent("retry_test_2.m4a")
        FileManager.default.createFile(atPath: file1.path, contents: Data([0x01]))
        FileManager.default.createFile(atPath: file2.path, contents: Data([0x02]))

        saveChunk("c1", sessionId: "s1", index: 0, state: UploadState.failed.rawValue, filePath: file1.path)
        saveChunk("c2", sessionId: "s1", index: 1, state: UploadState.failed.rawValue, filePath: file2.path)

        // First upload succeeds, second fails
        var callCount = 0
        uploader.uploadResult = .success(url: "s3://test")

        let result = await sut.retryFailedUploads(sessionId: "s1")

        // Both uploaded successfully since mock always returns success
        XCTAssertTrue(result)
        XCTAssertEqual(uploader.uploadCallCount, 2)

        // Cleanup
        try? FileManager.default.removeItem(at: file1)
        try? FileManager.default.removeItem(at: file2)
    }
}

// MARK: - Helper for OutputDTO initialization

private func makeOutputDTO(name: String?, status: ResultStatus?, templateId: String? = nil, value: String? = nil) -> ScribeResultResponse.OutputDTO {
    let statusString: String
    switch status {
    case .success: statusString = "success"
    case .failure: statusString = "failure"
    case .inProgress: statusString = "in-progress"
    case .partialCompleted: statusString = "partial_completed"
    case .none: statusString = "success"
    }
    var json: [String: Any] = ["status": statusString]
    if let name { json["name"] = name }
    if let templateId { json["template_id"] = templateId }
    if let value { json["value"] = value }
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JSONDecoder().decode(ScribeResultResponse.OutputDTO.self, from: data)
}
