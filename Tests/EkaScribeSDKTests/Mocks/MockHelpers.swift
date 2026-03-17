import Combine
import Foundation
@testable import EkaScribeSDK

// MARK: - MockLogger

final class MockLogger: Logger, @unchecked Sendable {
    struct LogEntry: Sendable {
        let level: String
        let tag: String
        let message: String
    }

    private let lock = NSLock()
    private var _entries: [LogEntry] = []

    var entries: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    func debug(_ tag: String, _ message: String) {
        append(LogEntry(level: "debug", tag: tag, message: message))
    }

    func info(_ tag: String, _ message: String) {
        append(LogEntry(level: "info", tag: tag, message: message))
    }

    func warn(_ tag: String, _ message: String, _ error: Error?) {
        append(LogEntry(level: "warn", tag: tag, message: message))
    }

    func error(_ tag: String, _ message: String, _ error: Error?) {
        append(LogEntry(level: "error", tag: tag, message: message))
    }

    private func append(_ entry: LogEntry) {
        lock.lock()
        _entries.append(entry)
        lock.unlock()
    }
}

// MARK: - MockTimeProvider

final class MockTimeProvider: TimeProvider {
    var currentTime: Int = 1_000_000

    func nowMillis() -> Int {
        currentTime
    }
}

// MARK: - MockVadProvider

final class MockVadProvider: VadProvider {
    var isSpeech = false
    var confidence: Float = 0.0
    var loadCalled = false
    var unloadCalled = false

    func load() { loadCalled = true }

    func detect(pcm: [Int16]) -> VadResult {
        VadResult(isSpeech: isSpeech, confidence: confidence)
    }

    func unload() { unloadCalled = true }
}

// MARK: - MockAudioEncoder

final class MockAudioEncoder: AudioEncoder {
    var encodeResult: EncodedChunk?
    var encodeError: Error?
    var encodeFromFileResult: EncodedChunk?
    var encodeFromFileError: Error?

    func encode(frames: [AudioFrame], sampleRate: Int, outputPath: String) async throws -> EncodedChunk {
        if let error = encodeError { throw error }
        if let result = encodeResult { return result }
        // Create a dummy file so tests that check file existence pass
        FileManager.default.createFile(atPath: outputPath, contents: Data([0x00]))
        return EncodedChunk(filePath: outputPath, format: .m4a, sizeBytes: 1, durationMs: 1000)
    }

    func encodeFromFile(pcmFilePath: String, sampleRate: Int, outputPath: String) async throws -> EncodedChunk {
        if let encodeFromFileError { throw encodeFromFileError }
        if let result = encodeFromFileResult { return result }
        FileManager.default.createFile(atPath: outputPath, contents: Data([0x00]))
        return EncodedChunk(filePath: outputPath, format: .m4a, sizeBytes: 1, durationMs: 1000)
    }
}

// MARK: - MockChunkUploader

final class MockChunkUploader: ChunkUploader {
    var uploadResult: UploadResult = .success(url: "s3://test/file.m4a")
    var uploadCallCount = 0
    var clearCacheCalled = false

    func upload(file: URL, metadata: UploadMetadata) async -> UploadResult {
        uploadCallCount += 1
        return uploadResult
    }

    func clearCache() async {
        clearCacheCalled = true
    }
}

// MARK: - MockDataManager

final class MockDataManager: DataManager {
    var sessions: [String: SessionRecord] = [:]
    var chunks: [String: AudioChunkRecord] = [:]

    func saveSession(_ session: SessionRecord) async throws {
        sessions[session.sessionId] = session
    }

    func getSession(_ sessionId: String) async throws -> SessionRecord? {
        sessions[sessionId]
    }

    func getAllSessions() async throws -> [SessionRecord] {
        Array(sessions.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteSession(_ sessionId: String) async throws {
        sessions.removeValue(forKey: sessionId)
    }

    func updateSessionState(_ sessionId: String, _ state: String) async throws {
        sessions[sessionId]?.state = state
    }

    func updateUploadStage(_ sessionId: String, _ stage: String) async throws {
        sessions[sessionId]?.uploadStage = stage
    }

    func updateSessionMetadata(_ sessionId: String, _ metadata: String) async throws {
        sessions[sessionId]?.sessionMetadata = metadata
    }

    func updateStageAndBid(_ sessionId: String, _ stage: String, _ bid: String) async throws {
        sessions[sessionId]?.uploadStage = stage
        sessions[sessionId]?.bid = bid
    }

    func updateFolderAndBid(_ sessionId: String, _ folderName: String, _ bid: String) async throws {
        sessions[sessionId]?.folderName = folderName
        sessions[sessionId]?.bid = bid
    }

    func getSessionsByStage(_ stage: String) async throws -> [SessionRecord] {
        sessions.values.filter { $0.uploadStage == stage }
    }

    func saveChunk(_ chunk: AudioChunkRecord) async throws {
        chunks[chunk.chunkId] = chunk
        sessions[chunk.sessionId]?.chunkCount += 1
    }

    func getAllChunks(sessionId: String) async throws -> [AudioChunkRecord] {
        chunks.values.filter { $0.sessionId == sessionId }.sorted { $0.chunkIndex < $1.chunkIndex }
    }

    func getUploadedChunks(sessionId: String) async throws -> [AudioChunkRecord] {
        chunks.values.filter { $0.sessionId == sessionId && $0.uploadState == UploadState.success.rawValue }
            .sorted { $0.chunkIndex < $1.chunkIndex }
    }

    func getChunkCount(sessionId: String) async throws -> Int {
        chunks.values.filter { $0.sessionId == sessionId }.count
    }

    func markInProgress(_ chunkId: String) async throws {
        chunks[chunkId]?.uploadState = UploadState.inProgress.rawValue
    }

    func markUploaded(_ chunkId: String) async throws {
        chunks[chunkId]?.uploadState = UploadState.success.rawValue
    }

    func markFailed(_ chunkId: String) async throws {
        chunks[chunkId]?.uploadState = UploadState.failed.rawValue
        chunks[chunkId]?.retryCount += 1
    }

    func areAllChunksUploaded(sessionId: String) async throws -> Bool {
        let all = chunks.values.filter { $0.sessionId == sessionId }
        guard !all.isEmpty else { return true }
        return all.allSatisfy { $0.uploadState == UploadState.success.rawValue }
    }

    func observeSession(_ sessionId: String) -> AnyPublisher<SessionRecord?, Never> {
        Just(sessions[sessionId]).eraseToAnyPublisher()
    }
}

// MARK: - MockAudioRecorder

final class MockAudioRecorder: AudioRecorder {
    var onFrame: ((AudioFrame) -> Void)?
    var onAudioFocusChanged: ((Bool) -> Void)?
    var startCalled = false
    var stopCalled = false
    var pauseCalled = false
    var resumeCalled = false

    func start() { startCalled = true }
    func stop() { stopCalled = true }
    func pause() { pauseCalled = true }
    func resume() { resumeCalled = true }
}

// MARK: - MockAudioAnalyser

final class MockAudioAnalyser: AudioAnalyser {
    var qualityFlow: AnyPublisher<AudioQuality, Never> {
        qualitySubject.eraseToAnyPublisher()
    }

    let qualitySubject = PassthroughSubject<AudioQuality, Never>()
    var submittedFrames: [AudioFrame] = []
    var releaseCalled = false

    func submitFrame(_ frame: AudioFrame) {
        submittedFrames.append(frame)
    }

    func release() {
        releaseCalled = true
    }
}

// MARK: - MockScribeAPIService

final class MockScribeAPIService: ScribeAPIServiceProtocol {
    var initResult: NetworkResult<InitTransactionResponse> = .success(
        InitTransactionResponse(bId: "test-bid", message: nil, status: nil, txnId: nil, error: nil),
        statusCode: 200
    )
    var stopResult: NetworkResult<StopTransactionResponse> = .success(
        StopTransactionResponse(message: nil, status: nil, error: nil),
        statusCode: 200
    )
    var commitResult: NetworkResult<StopTransactionResponse> = .success(
        StopTransactionResponse(message: nil, status: nil, error: nil),
        statusCode: 200
    )
    var getResultResult: NetworkResult<ScribeResultResponse> = .success(
        ScribeResultResponse(data: nil),
        statusCode: 200
    )

    var initCallCount = 0
    var stopCallCount = 0
    var commitCallCount = 0
    var getResultCallCount = 0

    func initTransaction(_ sessionId: String, _ request: InitTransactionRequest) async -> NetworkResult<InitTransactionResponse> {
        initCallCount += 1
        return initResult
    }

    func stopTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse> {
        stopCallCount += 1
        return stopResult
    }

    func commitTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse> {
        commitCallCount += 1
        return commitResult
    }

    func getTransactionResult(_ sessionId: String) async -> NetworkResult<ScribeResultResponse> {
        getResultCallCount += 1
        return getResultResult
    }
}

// MARK: - MockTransactionManager

final class MockTransactionManager: TransactionManaging {
    var initResult: TransactionResult = .success(folderName: "240101", bid: "test-bid")
    var retryResult: Bool = true
    var stopResult: TransactionResult = .success()
    var commitResult: TransactionResult = .success()
    var pollResult: TransactionPollResult = .success(result: ScribeResultResponse(data: nil))

    var initCallCount = 0
    var retryCallCount = 0
    var stopCallCount = 0
    var commitCallCount = 0
    var pollCallCount = 0

    func initTransaction(sessionId: String, sessionConfig: SessionConfig, folderName: String) async -> TransactionResult {
        initCallCount += 1
        return initResult
    }

    func retryFailedUploads(sessionId: String) async -> Bool {
        retryCallCount += 1
        return retryResult
    }

    func stopTransaction(sessionId: String) async -> TransactionResult {
        stopCallCount += 1
        return stopResult
    }

    func commitTransaction(sessionId: String) async -> TransactionResult {
        commitCallCount += 1
        return commitResult
    }

    func pollResult(sessionId: String) async -> TransactionPollResult {
        pollCallCount += 1
        return pollResult
    }
}

// MARK: - MockPipeline

final class MockPipeline: PipelineProtocol {
    var startCalled = false
    var startCoroutinesCalled = false
    var pauseCalled = false
    var resumeCalled = false
    var stopCalled = false
    var cancelCalled = false
    var stopResult: FullAudioResult?

    let audioFocusSubject = CurrentValueSubject<Bool, Never>(true)
    let audioQualitySubject = PassthroughSubject<AudioQualityMetrics, Never>()
    let voiceActivitySubject = PassthroughSubject<VoiceActivityData, Never>()

    var audioFocusFlow: AnyPublisher<Bool, Never> { audioFocusSubject.eraseToAnyPublisher() }
    var audioQualityFlow: AnyPublisher<AudioQualityMetrics, Never> { audioQualitySubject.eraseToAnyPublisher() }
    var voiceActivityFlow: AnyPublisher<VoiceActivityData, Never> { voiceActivitySubject.eraseToAnyPublisher() }

    func start() { startCalled = true }
    func startCoroutines() { startCoroutinesCalled = true }
    func pause() { pauseCalled = true }
    func resume() { resumeCalled = true }
    func stop() async -> FullAudioResult? {
        stopCalled = true
        return stopResult
    }
    func cancel() { cancelCalled = true }
}

// MARK: - MockPipelineFactory

final class MockPipelineFactory: PipelineCreating {
    var mockPipeline = MockPipeline()
    var createCallCount = 0
    var lastSessionId: String?

    func create(
        sessionId: String,
        folderName: String,
        bid: String,
        onEvent: ((SessionEventName, EventType, String, [String: String]) -> Void)? = nil
    ) -> PipelineProtocol {
        createCallCount += 1
        lastSessionId = sessionId
        return mockPipeline
    }
}

// MARK: - MockMicPermissionChecker

final class MockMicPermissionChecker: MicPermissionChecker {
    var permissionGranted = true

    func checkMicPermission() async -> Bool {
        permissionGranted
    }
}

// MARK: - MockEkaScribeDelegate

final class MockEkaScribeDelegate: EkaScribeDelegate {
    var didStartSessionId: String?
    var didPauseSessionId: String?
    var didResumeSessionId: String?
    var didStopSessionId: String?
    var didStopChunkCount: Int?
    var didFailError: ScribeError?
    var didCompleteSessionId: String?
    var didCompleteResult: SessionResult?
    var didFailSessionId: String?
    var didFailSessionError: ScribeError?
    var didChangeAudioFocusValue: Bool?
    var emittedEvents: [SessionEvent] = []

    func scribe(_ scribe: EkaScribe, didStartSession sessionId: String) {
        didStartSessionId = sessionId
    }
    func scribe(_ scribe: EkaScribe, didPauseSession sessionId: String) {
        didPauseSessionId = sessionId
    }
    func scribe(_ scribe: EkaScribe, didResumeSession sessionId: String) {
        didResumeSessionId = sessionId
    }
    func scribe(_ scribe: EkaScribe, didStopSession sessionId: String, chunkCount: Int) {
        didStopSessionId = sessionId
        didStopChunkCount = chunkCount
    }
    func scribe(_ scribe: EkaScribe, didFailWithError error: ScribeError) {
        didFailError = error
    }
    func scribe(_ scribe: EkaScribe, didCompleteSession sessionId: String, result: SessionResult) {
        didCompleteSessionId = sessionId
        didCompleteResult = result
    }
    func scribe(_ scribe: EkaScribe, didFailSession sessionId: String, error: ScribeError) {
        didFailSessionId = sessionId
        didFailSessionError = error
    }
    func scribe(_ scribe: EkaScribe, didChangeAudioFocus hasFocus: Bool) {
        didChangeAudioFocusValue = hasFocus
    }
    func scribe(_ scribe: EkaScribe, didEmitEvent event: SessionEvent) {
        emittedEvents.append(event)
    }
}

// MARK: - MockAudioChunker

final class MockAudioChunker: AudioChunker {
    var feedResult: AudioChunk?
    var flushResult: AudioChunk?
    var latestQuality: AudioQuality?
    var releaseCalled = false
    let activitySubject = PassthroughSubject<VoiceActivityData, Never>()

    var activityFlow: AnyPublisher<VoiceActivityData, Never> {
        activitySubject.eraseToAnyPublisher()
    }

    func feed(_ frame: AudioFrame) -> AudioChunk? { feedResult }
    func flush() -> AudioChunk? { flushResult }
    func setLatestQuality(_ quality: AudioQuality?) { latestQuality = quality }
    func release() { releaseCalled = true }
}

// MARK: - MockTokenStorage

final class MockTokenStorage: EkaScribeTokenStorage {
    var accessToken: String? = "test-token"
    var refreshToken: String? = "test-refresh-token"
    var savedAccessToken: String?
    var savedRefreshToken: String?
    var sessionExpiredCalled = false

    func getAccessToken() -> String? { accessToken }
    func getRefreshToken() -> String? { refreshToken }

    func saveTokens(accessToken: String, refreshToken: String) {
        savedAccessToken = accessToken
        savedRefreshToken = refreshToken
    }

    func onSessionExpired() {
        sessionExpiredCalled = true
    }
}

// MARK: - Test Helpers

func makeFrame(pcm: [Int16] = Array(repeating: 0, count: 512), timestampMs: Int = 0, sampleRate: Int = 16000, frameIndex: Int = 0) -> AudioFrame {
    AudioFrame(pcm: pcm, timestampMs: timestampMs, sampleRate: sampleRate, frameIndex: frameIndex)
}

func makeSpeechFrame(sampleCount: Int = 512, timestampMs: Int = 0, amplitude: Int16 = 10000) -> AudioFrame {
    let pcm = Array(repeating: amplitude, count: sampleCount)
    return AudioFrame(pcm: pcm, timestampMs: timestampMs, sampleRate: 16000, frameIndex: 0)
}
