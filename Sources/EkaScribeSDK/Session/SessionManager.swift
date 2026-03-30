import Combine
import Foundation

final class SessionManager: @unchecked Sendable {
    private let config: EkaScribeConfig
    private let dataManager: DataManager
    private let pipelineFactory: PipelineCreating
    private let transactionManager: TransactionManaging
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
    private(set) var pipeline: PipelineProtocol?
    private weak var delegate: EkaScribeDelegate?
    private var eventEmitter: SessionEventEmitter?
    private var stopTask: Task<Void, Never>?
    private var flowCancellables: Set<AnyCancellable> = []
    private(set) var lastFullAudioPath: String?
    private let micPermissionChecker: MicPermissionChecker

    init(
        config: EkaScribeConfig,
        dataManager: DataManager,
        pipelineFactory: PipelineCreating,
        transactionManager: TransactionManaging,
        chunkUploader: ChunkUploader,
        timeProvider: TimeProvider,
        logger: Logger,
        micPermissionChecker: MicPermissionChecker = DefaultMicPermissionChecker()
    ) {
        self.config = config
        self.dataManager = dataManager
        self.pipelineFactory = pipelineFactory
        self.transactionManager = transactionManager
        self.chunkUploader = chunkUploader
        self.timeProvider = timeProvider
        self.logger = logger
        self.micPermissionChecker = micPermissionChecker
    }

    func setDelegate(_ delegate: EkaScribeDelegate) {
        self.delegate = delegate
    }

    func start(
        sessionConfig: SessionConfig,
        onStart: (String) -> Void,
        onError: (ScribeError) -> Void
    ) async {
        guard await micPermissionChecker.checkMicPermission() else {
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
            let errorCode: ErrorCode
            if case .error(let errorMessage, let code) = initResult {
                message = errorMessage
                errorCode = code ?? .initTransactionFailed
            } else {
                message = "Init failed"
                errorCode = .initTransactionFailed
            }
            let error = ScribeError(code: errorCode, message: message)
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

        do {
            try pipeline?.start()
        } catch {
            transition(to: .error)
            let scribeError = ScribeError(code: .recorderSetupFailed, message: "Recorder setup failed: \(error.localizedDescription)")
            delegate?.scribe(EkaScribe.shared, didFailWithError: scribeError)
            onError(scribeError)
            eventEmitter?.emit(.recorderSetupFailed, .error, scribeError.message)
            cleanup()
            return
        }

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
                cleanup()
            }

            let fullAudioResult = await self.pipeline?.stop()
            let chunkCount = (try? await self.dataManager.getChunkCount(sessionId: sessionId)) ?? 0
            self.eventEmitter?.emit(.pipelineStopped, .info, "Pipeline stopped")
            self.delegate?.scribe(EkaScribe.shared, didStopSession: sessionId, chunkCount: chunkCount)

            self.transition(to: .processing)

            self.eventEmitter?.emit(.uploadRetryStarted, .info, "Retrying uploads")
            let allUploaded = await self.transactionManager.retryFailedUploads(
                sessionId: sessionId,
                onChunkEvent: { [weak self] name, type, message, metadata in
                    self?.eventEmitter?.emit(name, type, message, metadata)
                }
            )
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
                if case .error(let errorMessage, _) = stopResult {
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
                if case .error(let errorMessage, _) = commitResult {
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
                self.eventEmitter?.emit(.pollResultSuccess, .success, "Poll result received successfully")
                try? await self.dataManager.updateSessionState(sessionId, SessionState.completed.rawValue)
                self.transition(to: .completed)
                let result = Self.mapToSessionResult(sessionId: sessionId, response)
                self.eventEmitter?.emit(.sessionResultReceived, .success, "Session result received", [
                    "templateCount": "\(result.templates.count)"
                ])
                self.eventEmitter?.emit(.sessionCompleted, .success, "Session completed")
                self.delegate?.scribe(EkaScribe.shared, didCompleteSession: sessionId, result: result)

            case .failed(let error):
                self.eventEmitter?.emit(.pollResultFailed, .error, "Poll result failed: \(error)")
                self.handleError(sessionId: sessionId, code: .transcriptionFailed, message: error)

            case .timeout:
                self.transition(to: .completed)
                self.eventEmitter?.emit(.pollResultTimeout, .info, "Poll timeout")
            }

            if let fullAudioResult {
                self.lastFullAudioPath = fullAudioResult.filePath
                Task { [weak self] in
                    guard let self else { return }
                    await self.uploadFullAudio(fullAudioResult)
                }
            }
        }
    }

    func cancel() {
        guard [.recording, .paused].contains(currentState) else { return }
        let sessionId = activeSessionId

        pipeline?.cancel()
        Task { await chunkUploader.clearCache() }

        if let sessionId {
            Task {
                try? await dataManager.updateUploadStage(sessionId, TransactionStage.cancelled.rawValue)
            }
        }

        eventEmitter?.emit(.sessionCancelled, .info, "Session cancelled")

        if let sessionId {
            delegate?.scribe(EkaScribe.shared, didCancelSession: sessionId)
        }

        cleanup()
        transition(to: .idle)
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
        pipeline?.cancel()
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
                    pause()
                }
                eventEmitter?.emit(.audioFocusChanged, .info, hasFocus ? "Audio focus gained" : "Audio focus lost", ["hasFocus": "\(hasFocus)"])
                delegate?.scribe(EkaScribe.shared, didChangeAudioFocus: hasFocus)
            }
            .store(in: &flowCancellables)
    }

    func uploadFullAudio(_ result: FullAudioResult) async {
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
                    type: output.templateType ?? .markdown,
                    rawOutput: output.value
                )
            )
        }

        let audioQuality = response.data?.audioMatrix?.quality
        return SessionResult(templates: templates, audioQuality: audioQuality)
    }
}
