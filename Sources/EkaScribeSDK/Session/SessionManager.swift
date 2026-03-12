import AVFoundation
import Combine
import Foundation

final class SessionManager: @unchecked Sendable {
    private let config: EkaScribeConfig
    private let dataManager: DataManager
    private let pipelineFactory: Pipeline.Factory
    private let transactionManager: TransactionManager
    private let chunkUploader: ChunkUploader
    private let timeProvider: TimeProvider
    private let logger: Logger

    private let stateSubject = CurrentValueSubject<SessionState, Never>(.idle)
    var stateFlow: AnyPublisher<SessionState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentState: SessionState { stateSubject.value }

    // Stable flows that survive pipeline lifecycle (matching Android)
    private let voiceActivitySubject = PassthroughSubject<VoiceActivityData, Never>()
    private let audioQualitySubject = PassthroughSubject<AudioQualityMetrics, Never>()
    var voiceActivityFlow: AnyPublisher<VoiceActivityData, Never> { voiceActivitySubject.eraseToAnyPublisher() }
    var audioQualityFlow: AnyPublisher<AudioQualityMetrics, Never> { audioQualitySubject.eraseToAnyPublisher() }

    private var activeSessionId: String?
    private var activeSessionConfig: SessionConfig?
    private(set) var pipeline: Pipeline?
    private weak var delegate: EkaScribeDelegate?
    private var eventEmitter: SessionEventEmitter?
    private var stopTask: Task<Void, Never>?
    private var flowCancellables: Set<AnyCancellable> = []
    private(set) var lastFullAudioPath: String?

    init(
        config: EkaScribeConfig,
        dataManager: DataManager,
        pipelineFactory: Pipeline.Factory,
        transactionManager: TransactionManager,
        chunkUploader: ChunkUploader,
        timeProvider: TimeProvider,
        logger: Logger
    ) {
        self.config = config
        self.dataManager = dataManager
        self.pipelineFactory = pipelineFactory
        self.transactionManager = transactionManager
        self.chunkUploader = chunkUploader
        self.timeProvider = timeProvider
        self.logger = logger
    }

    func setDelegate(_ delegate: EkaScribeDelegate) {
        self.delegate = delegate
    }

    func start(
        sessionConfig: SessionConfig,
        onStart: (String) -> Void,
        onError: (ScribeError) -> Void
    ) async {
        guard await checkMicPermission() else {
            onError(ScribeError(code: .micPermissionDenied, message: "Microphone permission denied"))
            return
        }

        let current = currentState
        if current != .idle {
            if current == .completed || current == .error {
                // Previous session ended — clean up and reset
                cleanup()
                transition(to: .idle)
            } else {
                onError(ScribeError(code: .sessionAlreadyActive, message: "Cannot start new session from state: \(current.rawValue). Stop the current session first."))
                return
            }
        }

        transition(to: .starting)

        let sessionId = IdGenerator.sessionId()
        activeSessionId = sessionId
        activeSessionConfig = sessionConfig
        eventEmitter = SessionEventEmitter(delegate: delegate, scribe: EkaScribe.shared, sessionId: sessionId)
        eventEmitter?.emit(.sessionStartInitiated, .info, "Session start initiated")

        let folderName = TransactionManager.defaultFolderName()

        let session = SessionRecord(
            sessionId: sessionId,
            createdAt: timeProvider.nowMillis(),
            updatedAt: timeProvider.nowMillis(),
            state: SessionState.starting.rawValue,
            chunkCount: 0,
            mode: sessionConfig.mode,
            ownerId: nil,
            metadata: nil,
            uploadStage: TransactionStage.initialize.rawValue,
            sessionMetadata: nil,
            folderName: folderName,
            bid: nil
        )
        try? await dataManager.saveSession(session)

        let initResult = await transactionManager.initTransaction(sessionId: sessionId, sessionConfig: sessionConfig, folderName: folderName)

        guard case .success(_, let bid) = initResult else {
            transition(to: .error)
            let message: String
            if case .error(let errorMessage) = initResult {
                message = errorMessage
            } else {
                message = "Init failed"
            }
            let error = ScribeError(code: .initTransactionFailed, message: message)
            delegate?.scribe(EkaScribe.shared, didFailWithError: error)
            onError(error)
            eventEmitter?.emit(.initTransactionFailed, .error, message)
            return
        }

        eventEmitter?.emit(.initTransactionSuccess, .success, "Init transaction success")

        pipeline = pipelineFactory.create(
            sessionId: sessionId,
            folderName: folderName,
            bid: bid,
            onEvent: { [weak self] name, type, message, metadata in
                self?.eventEmitter?.emit(name, type, message, metadata)
            }
        )
        pipeline?.start()
        startFlowCollection()

        transition(to: .recording)
        delegate?.scribe(EkaScribe.shared, didStartSession: sessionId)
        eventEmitter?.emit(.recordingStarted, .success, "Recording started")
        onStart(sessionId)
    }

    func pause() {
        guard currentState == .recording else { return }
        pipeline?.pause()
        transition(to: .paused)
        eventEmitter?.emit(.sessionPaused, .info, "Session paused")
        if let id = activeSessionId {
            delegate?.scribe(EkaScribe.shared, didPauseSession: id)
        }
    }

    func resume() {
        guard currentState == .paused else { return }
        pipeline?.resume()
        transition(to: .recording)
        eventEmitter?.emit(.sessionResumed, .info, "Session resumed")
        if let id = activeSessionId {
            delegate?.scribe(EkaScribe.shared, didResumeSession: id)
        }
    }

    func stop() {
        guard [.recording, .paused].contains(currentState) else { return }
        transition(to: .stopping)
        eventEmitter?.emit(.sessionStopInitiated, .info, "Session stop initiated")

        stopTask = Task { [weak self] in
            guard let self, let sessionId = self.activeSessionId else { return }
            defer {
                self.cleanup()
            }

            let fullAudioResult = await self.pipeline?.stop()
            let chunkCount = (try? await self.dataManager.getChunkCount(sessionId: sessionId)) ?? 0
            self.eventEmitter?.emit(.pipelineStopped, .info, "Pipeline stopped")
            self.delegate?.scribe(EkaScribe.shared, didStopSession: sessionId, chunkCount: chunkCount)

            self.transition(to: .processing)

            self.eventEmitter?.emit(.uploadRetryStarted, .info, "Retrying uploads")
            let allUploaded = await self.transactionManager.retryFailedUploads(sessionId: sessionId)
            self.eventEmitter?.emit(
                .uploadRetryCompleted,
                allUploaded ? .success : .error,
                "Upload retry \(allUploaded ? "success" : "partial")"
            )

            if !allUploaded {
                self.handleError(sessionId: sessionId, code: .retryExhausted, message: "Not all chunks uploaded")
                return
            }

            let stopResult = await self.transactionManager.stopTransaction(sessionId: sessionId)
            guard case .success = stopResult else {
                let message: String
                if case .error(let errorMessage) = stopResult {
                    message = errorMessage
                } else {
                    message = "Stop failed"
                }
                self.handleError(sessionId: sessionId, code: .stopTransactionFailed, message: message)
                return
            }
            self.eventEmitter?.emit(.stopTransactionSuccess, .success, "Stop transaction success")

            let commitResult = await self.transactionManager.commitTransaction(sessionId: sessionId)
            guard case .success = commitResult else {
                let message: String
                if case .error(let errorMessage) = commitResult {
                    message = errorMessage
                } else {
                    message = "Commit failed"
                }
                self.handleError(sessionId: sessionId, code: .commitTransactionFailed, message: message)
                return
            }
            self.eventEmitter?.emit(.commitTransactionSuccess, .success, "Commit transaction success")

            switch await self.transactionManager.pollResult(sessionId: sessionId) {
            case .success(let response):
                try? await self.dataManager.updateSessionState(sessionId, SessionState.completed.rawValue)
                self.transition(to: .completed)
                let result = Self.mapToSessionResult(sessionId: sessionId, response)
                self.eventEmitter?.emit(.sessionCompleted, .success, "Session completed")
                self.delegate?.scribe(EkaScribe.shared, didCompleteSession: sessionId, result: result)

            case .failed(let error):
                self.handleError(sessionId: sessionId, code: .transcriptionFailed, message: error)

            case .timeout:
                self.transition(to: .completed)
                self.eventEmitter?.emit(.pollResultTimeout, .info, "Poll timeout")
            }

            if let fullAudioResult {
                self.lastFullAudioPath = fullAudioResult.filePath
                Task.detached { [weak self] in
                    await self?.uploadFullAudio(fullAudioResult)
                }
            }
        }
    }

    func destroy() {
        stopTask?.cancel()
        cleanup()
        transition(to: .idle)
    }

    private func transition(to newState: SessionState) {
        guard stateSubject.value.canTransition(to: newState) else {
            logger.warn("SessionManager", "Invalid transition: \(stateSubject.value.rawValue) -> \(newState.rawValue)")
            return
        }

        stateSubject.send(newState)

        if let sessionId = activeSessionId {
            Task {
                try? await dataManager.updateSessionState(sessionId, newState.rawValue)
            }
        }
    }

    private func cleanup() {
        flowCancellables.removeAll()
        pipeline = nil
        activeSessionId = nil
        activeSessionConfig = nil
        eventEmitter = nil
    }

    private func handleError(sessionId: String, code: ErrorCode, message: String) {
        transition(to: .error)
        let error = ScribeError(code: code, message: message)
        delegate?.scribe(EkaScribe.shared, didFailWithError: error)
        delegate?.scribe(EkaScribe.shared, didFailSession: sessionId, error: error)
        eventEmitter?.emit(.sessionFailed, .error, message)
    }

    private func startFlowCollection() {
        flowCancellables.removeAll()

        pipeline?.voiceActivityFlow
            .sink { [weak self] data in
                self?.voiceActivitySubject.send(data)
            }
            .store(in: &flowCancellables)

        pipeline?.audioQualityFlow
            .sink { [weak self] data in
                self?.audioQualitySubject.send(data)
            }
            .store(in: &flowCancellables)

        pipeline?.audioFocusFlow
            .sink { [weak self] hasFocus in
                guard let self else { return }
                if !hasFocus {
                    self.pause()
                }
                self.eventEmitter?.emit(.audioFocusChanged, .info, hasFocus ? "Audio focus gained" : "Audio focus lost", ["hasFocus": "\(hasFocus)"])
                self.delegate?.scribe(EkaScribe.shared, didChangeAudioFocus: hasFocus)
            }
            .store(in: &flowCancellables)
    }

    private func checkMicPermission() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }

        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
        #else
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
        #endif
    }

    private func uploadFullAudio(_ result: FullAudioResult) async {
        let file = URL(fileURLWithPath: result.filePath)
        let format = EncodedChunk.AudioFormat.from(filePath: result.filePath)
        let metadata = UploadMetadata(
            chunkId: "\(result.sessionId)_full",
            sessionId: result.sessionId,
            chunkIndex: Int.max,
            fileName: "full_audio.\(format.fileExtension)_",
            folderName: result.folderName,
            bid: result.bid,
            mimeType: format.mimeType
        )

        switch await chunkUploader.upload(file: file, metadata: metadata) {
        case .success:
            eventEmitter?.emit(.fullAudioUploaded, .success, "Full audio uploaded")

        case .failure(let error, _):
            eventEmitter?.emit(.fullAudioUploadFailed, .error, "Full audio upload failed: \(error)")
        }
    }

    static func mapToSessionResult(sessionId: String, _ response: ScribeResultResponse) -> SessionResult {
        var templates: [TemplateOutput] = []

        let outputs = response.data?.output?.compactMap { $0 } ?? []
        for output in outputs {
            let decoded = output.value.flatMap { Data(base64Encoded: $0) }.flatMap { String(data: $0, encoding: .utf8) }
            let section = SectionData(title: output.name, value: decoded ?? output.value)
            templates.append(
                TemplateOutput(
                    name: output.name,
                    title: output.name,
                    sections: [section],
                    sessionId: sessionId,
                    templateId: output.templateId,
                    isEditable: true,
                    type: (output.type == "json") ? .json : .markdown,
                    rawOutput: output.value
                )
            )
        }

        let audioQuality = response.data?.audioMatrix?.quality
        return SessionResult(templates: templates, audioQuality: audioQuality)
    }
}
