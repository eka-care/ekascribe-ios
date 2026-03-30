import XCTest
@testable import EkaScribeSDK

final class UploadAndTransactionTests: XCTestCase {

    // MARK: - ErrorCode

    func testErrorCodeRawValues() {
        XCTAssertEqual(ErrorCode.micPermissionDenied.rawValue, "micPermissionDenied")
        XCTAssertEqual(ErrorCode.sessionAlreadyActive.rawValue, "sessionAlreadyActive")
        XCTAssertEqual(ErrorCode.invalidConfig.rawValue, "invalidConfig")
        XCTAssertEqual(ErrorCode.encoderFailed.rawValue, "encoderFailed")
        XCTAssertEqual(ErrorCode.uploadFailed.rawValue, "uploadFailed")
        XCTAssertEqual(ErrorCode.modelLoadFailed.rawValue, "modelLoadFailed")
        XCTAssertEqual(ErrorCode.networkUnavailable.rawValue, "networkUnavailable")
        XCTAssertEqual(ErrorCode.dbError.rawValue, "dbError")
        XCTAssertEqual(ErrorCode.invalidStateTransition.rawValue, "invalidStateTransition")
        XCTAssertEqual(ErrorCode.initTransactionFailed.rawValue, "initTransactionFailed")
        XCTAssertEqual(ErrorCode.stopTransactionFailed.rawValue, "stopTransactionFailed")
        XCTAssertEqual(ErrorCode.commitTransactionFailed.rawValue, "commitTransactionFailed")
        XCTAssertEqual(ErrorCode.pollTimeout.rawValue, "pollTimeout")
        XCTAssertEqual(ErrorCode.transcriptionFailed.rawValue, "transcriptionFailed")
        XCTAssertEqual(ErrorCode.retryExhausted.rawValue, "retryExhausted")
        XCTAssertEqual(ErrorCode.unknown.rawValue, "unknown")
    }

    func testErrorCodeCodable() throws {
        let data = try JSONEncoder().encode(ErrorCode.encoderFailed)
        let decoded = try JSONDecoder().decode(ErrorCode.self, from: data)
        XCTAssertEqual(decoded, .encoderFailed)
    }

    // MARK: - UploadState

    func testUploadStateRawValues() {
        XCTAssertEqual(UploadState.pending.rawValue, "PENDING")
        XCTAssertEqual(UploadState.inProgress.rawValue, "IN_PROGRESS")
        XCTAssertEqual(UploadState.success.rawValue, "SUCCESS")
        XCTAssertEqual(UploadState.failed.rawValue, "FAILED")
    }

    // MARK: - TransactionStage

    func testTransactionStageRawValues() {
        XCTAssertEqual(TransactionStage.initialize.rawValue, "INIT")
        XCTAssertEqual(TransactionStage.stop.rawValue, "STOP")
        XCTAssertEqual(TransactionStage.commit.rawValue, "COMMIT")
        XCTAssertEqual(TransactionStage.analyzing.rawValue, "ANALYZING")
        XCTAssertEqual(TransactionStage.completed.rawValue, "COMPLETED")
        XCTAssertEqual(TransactionStage.failure.rawValue, "FAILURE")
        XCTAssertEqual(TransactionStage.error.rawValue, "ERROR")
    }

    // MARK: - UploadStage (public)

    func testUploadStageRawValues() {
        XCTAssertEqual(UploadStage.initialize.rawValue, "INIT")
        XCTAssertEqual(UploadStage.stop.rawValue, "STOP")
        XCTAssertEqual(UploadStage.commit.rawValue, "COMMIT")
        XCTAssertEqual(UploadStage.analyzing.rawValue, "ANALYZING")
        XCTAssertEqual(UploadStage.completed.rawValue, "COMPLETED")
        XCTAssertEqual(UploadStage.failure.rawValue, "FAILURE")
        XCTAssertEqual(UploadStage.error.rawValue, "ERROR")
    }

    // MARK: - TransactionResult

    func testTransactionResultSuccess() {
        let result = TransactionResult.success(folderName: "240101", bid: "bid123")
        if case .success(let folder, let bid) = result {
            XCTAssertEqual(folder, "240101")
            XCTAssertEqual(bid, "bid123")
        } else {
            XCTFail("Expected success")
        }
    }

    func testTransactionResultError() {
        let result = TransactionResult.error(message: "Network error")
        if case .error(let message, _) = result {
            XCTAssertEqual(message, "Network error")
        } else {
            XCTFail("Expected error")
        }
    }

    func testTransactionResultSuccessDefaults() {
        let result = TransactionResult.success()
        if case .success(let folder, let bid) = result {
            XCTAssertEqual(folder, "")
            XCTAssertEqual(bid, "")
        } else {
            XCTFail("Expected success")
        }
    }

    // MARK: - UploadResult

    func testUploadResultSuccess() {
        let result = UploadResult.success(url: "s3://bucket/file.m4a")
        if case .success(let url) = result {
            XCTAssertEqual(url, "s3://bucket/file.m4a")
        } else {
            XCTFail("Expected success")
        }
    }

    func testUploadResultFailure() {
        let result = UploadResult.failure(error: "Not found", isRetryable: false)
        if case .failure(let error, let retryable) = result {
            XCTAssertEqual(error, "Not found")
            XCTAssertFalse(retryable)
        } else {
            XCTFail("Expected failure")
        }
    }

    // MARK: - TemplateType

    func testTemplateTypeRawValues() {
        XCTAssertEqual(TemplateType.markdown.rawValue, "markdown")
        XCTAssertEqual(TemplateType.json.rawValue, "json")
        XCTAssertEqual(TemplateType.ekaEmr.rawValue, "eka_emr")
    }

    // MARK: - EventType

    func testEventTypeRawValues() {
        XCTAssertEqual(EventType.success.rawValue, "success")
        XCTAssertEqual(EventType.error.rawValue, "error")
        XCTAssertEqual(EventType.info.rawValue, "info")
    }

    // MARK: - SessionEvent

    func testSessionEventInit() {
        let event = SessionEvent(
            sessionId: "s1",
            eventName: .recordingStarted,
            eventType: .success,
            message: "Started",
            timestampMs: 12345
        )
        XCTAssertEqual(event.sessionId, "s1")
        XCTAssertEqual(event.eventName, .recordingStarted)
        XCTAssertEqual(event.eventType, .success)
        XCTAssertEqual(event.message, "Started")
        XCTAssertTrue(event.metadata.isEmpty)
        XCTAssertEqual(event.timestampMs, 12345)
    }

    func testSessionEventWithMetadata() {
        let event = SessionEvent(
            sessionId: "s1",
            eventName: .chunkUploaded,
            eventType: .info,
            message: "Uploaded",
            metadata: ["chunkId": "c1"],
            timestampMs: 100
        )
        XCTAssertEqual(event.metadata["chunkId"], "c1")
    }

    // MARK: - UploadMetadata

    func testUploadMetadataDefaultMimeType() {
        let meta = UploadMetadata(
            chunkId: "c1",
            sessionId: "s1",
            chunkIndex: 0,
            fileName: "1.m4a",
            folderName: "240101",
            bid: "bid"
        )
        XCTAssertEqual(meta.mimeType, "audio/mp4")
    }

    func testUploadMetadataCustomMimeType() {
        let meta = UploadMetadata(
            chunkId: "c1",
            sessionId: "s1",
            chunkIndex: 0,
            fileName: "1.wav",
            folderName: "240101",
            bid: "bid",
            mimeType: "audio/wav"
        )
        XCTAssertEqual(meta.mimeType, "audio/wav")
    }

    // MARK: - SessionConfig

    func testSessionConfigDefaults() {
        let config = SessionConfig(languages: ["en-IN"], mode: "dictation", modelType: "pro")
        XCTAssertEqual(config.languages, ["en-IN"])
        XCTAssertEqual(config.mode, "dictation")
        XCTAssertEqual(config.modelType, "pro")
        XCTAssertNil(config.outputTemplates)
        XCTAssertNil(config.patientDetails)
        XCTAssertNil(config.section)
        XCTAssertNil(config.speciality)
    }

    func testSessionConfigCustom() {
        let config = SessionConfig(
            languages: ["hi-IN", "en-IN"],
            mode: "conversation",
            modelType: "lite",
            section: "cardiology",
            speciality: "internal_medicine"
        )
        XCTAssertEqual(config.languages, ["hi-IN", "en-IN"])
        XCTAssertEqual(config.mode, "conversation")
        XCTAssertEqual(config.section, "cardiology")
    }

    // MARK: - PipelineConfig

    func testPipelineConfigDefaults() {
        let config = PipelineConfig()
        XCTAssertEqual(config.frameChannelCapacity, 640)
        XCTAssertEqual(config.chunkChannelCapacity, 80)
        XCTAssertTrue(config.enableAnalyser)
        XCTAssertEqual(config.preBufferCapacity, 2000)
    }

    func testPipelineConfigCustom() {
        let config = PipelineConfig(frameChannelCapacity: 100, chunkChannelCapacity: 10, enableAnalyser: false, preBufferCapacity: 500)
        XCTAssertEqual(config.frameChannelCapacity, 100)
        XCTAssertFalse(config.enableAnalyser)
    }

    // MARK: - RecorderConfig

    func testRecorderConfig() {
        let config = RecorderConfig(sampleRate: 16000, frameSize: 512)
        XCTAssertEqual(config.sampleRate, 16000)
        XCTAssertEqual(config.channels, 1)
        XCTAssertEqual(config.frameSize, 512)
    }

    // MARK: - VadResult

    func testVadResult() {
        let result = VadResult(isSpeech: true, confidence: 0.95)
        XCTAssertTrue(result.isSpeech)
        XCTAssertEqual(result.confidence, 0.95, accuracy: 0.001)
    }

    // MARK: - FullAudioResult

    func testFullAudioResult() {
        let result = FullAudioResult(filePath: "/tmp/audio.m4a", sessionId: "s1", folderName: "240101", bid: "bid")
        XCTAssertEqual(result.filePath, "/tmp/audio.m4a")
        XCTAssertEqual(result.sessionId, "s1")
        XCTAssertEqual(result.folderName, "240101")
        XCTAssertEqual(result.bid, "bid")
    }

    // MARK: - VoiceActivityData

    func testVoiceActivityData() {
        let data = VoiceActivityData(isSpeech: true, amplitude: 0.5, timestampMs: 1000)
        XCTAssertTrue(data.isSpeech)
        XCTAssertEqual(data.amplitude, 0.5, accuracy: 0.001)
        XCTAssertEqual(data.timestampMs, 1000)
    }

    // MARK: - AudioQualityMetrics

    func testAudioQualityMetrics() {
        let metrics = AudioQualityMetrics(stoi: 0.8, pesq: 3.5, siSDR: 10.0, overallScore: 0.75)
        XCTAssertEqual(metrics.stoi, 0.8, accuracy: 0.001)
        XCTAssertEqual(metrics.pesq, 3.5, accuracy: 0.001)
        XCTAssertEqual(metrics.siSDR, 10.0, accuracy: 0.001)
        XCTAssertEqual(metrics.overallScore, 0.75, accuracy: 0.001)
    }

    // MARK: - SessionResult

    func testSessionResultInit() {
        let result = SessionResult(templates: [], audioQuality: 0.85)
        XCTAssertTrue(result.templates.isEmpty)
        XCTAssertEqual(result.audioQuality, 0.85)
    }

    func testSessionResultNoQuality() {
        let result = SessionResult(templates: [])
        XCTAssertNil(result.audioQuality)
    }

    // MARK: - AudioFrame

    func testAudioFrame() {
        let frame = AudioFrame(pcm: [100, -200, 300], timestampMs: 5000, sampleRate: 16000, frameIndex: 42)
        XCTAssertEqual(frame.pcm.count, 3)
        XCTAssertEqual(frame.timestampMs, 5000)
        XCTAssertEqual(frame.sampleRate, 16000)
        XCTAssertEqual(frame.frameIndex, 42)
    }
}
