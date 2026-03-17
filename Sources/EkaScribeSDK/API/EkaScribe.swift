import Combine
import Foundation

public final class EkaScribe: @unchecked Sendable {
    public static let shared = EkaScribe()

    private init() {}

    private var sessionManager: SessionManager?
    private var transactionManager: TransactionManager?
    private var dataManager: DataManager?
    private var networkClient: ScribeNetworkClient?
    private var apiService: ScribeAPIServiceProtocol?
    private var modelDownloader: ModelDownloader?
    private var isInitialized = false
    private var config: EkaScribeConfig?
    private var cancellables: Set<AnyCancellable> = []

    @Published public private(set) var analyserState: AnalyserState = .idle

    public func initialize(config: EkaScribeConfig, delegate: EkaScribeDelegate) throws {
        let logger: Logger = config.debugMode ? DefaultLogger() : NoOpLogger()
        let timeProvider = DefaultTimeProvider()

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let filesDir = appSupport.appendingPathComponent("EkaScribeSDK")
        try? FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)

        let dbPath = filesDir.appendingPathComponent("eka_scribe.sqlite").path
        let database: ScribeDatabase
        do {
            database = try ScribeDatabase(path: dbPath)
        } catch {
            throw error
        }

        let dataManager = DefaultDataManager(database: database, timeProvider: timeProvider, logger: logger)

        let networkClient = ScribeNetworkClient(
            baseURL: config.baseURL,
            clientInfo: config.clientInfo,
            tokenStorage: config.tokenStorage,
            refreshTokenPath: config.refreshTokenPath,
            logger: logger
        )
        let apiService = ScribeAPIService(networkClient: networkClient)

        let credentialProvider = S3CredentialProvider(
            credentialsURL: config.credentialsURL,
            networkClient: networkClient,
            logger: logger
        )
        let chunkUploader = S3ChunkUploader(
            credentialProvider: credentialProvider,
            bucketName: config.bucketName,
            maxRetryCount: config.maxUploadRetries,
            logger: logger
        )

        let encoder = M4aAudioEncoder(logger: logger)

        let downloader = ModelDownloader(filesDir: filesDir, logger: logger)

        let outputDir = filesDir.appendingPathComponent("output")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let pipelineFactory = Pipeline.Factory(
            config: config,
            dataManager: dataManager,
            encoder: encoder,
            chunkUploader: chunkUploader,
            modelDownloader: downloader,
            outputDir: outputDir,
            timeProvider: timeProvider,
            logger: logger
        )

        let transactionManager = TransactionManager(
            apiService: apiService,
            dataManager: dataManager,
            chunkUploader: chunkUploader,
            bucketName: config.bucketName,
            maxUploadRetries: config.maxUploadRetries,
            pollMaxRetries: config.pollMaxRetries,
            pollDelayMs: config.pollDelayMs,
            logger: logger
        )

        let sessionManager = SessionManager(
            config: config,
            dataManager: dataManager,
            pipelineFactory: pipelineFactory,
            transactionManager: transactionManager,
            chunkUploader: chunkUploader,
            timeProvider: timeProvider,
            logger: logger
        )
        sessionManager.setDelegate(delegate)

        self.config = config
        self.sessionManager = sessionManager
        self.transactionManager = transactionManager
        self.dataManager = dataManager
        self.networkClient = networkClient
        self.apiService = apiService
        self.modelDownloader = downloader
        self.isInitialized = true

        downloader.$state
            .sink { [weak self] state in
                guard let self else { return }
                analyserState = state
            }
            .store(in: &cancellables)

        if config.enableAnalyser {
            Task { await downloader.downloadIfNeeded() }
        } else {
            analyserState = .disabled
        }
    }

    public func startSession(
        config: SessionConfig,
        onStart: @escaping (String) -> Void = { _ in },
        onError: @escaping (ScribeError) -> Void = { _ in }
    ) async throws {
        let manager = try requireInitialized()
        await manager.start(sessionConfig: config, onStart: onStart, onError: onError)
    }

    public func pauseSession() {
        sessionManager?.pause()
    }

    public func resumeSession() {
        sessionManager?.resume()
    }

    public func stopSession() {
        sessionManager?.stop()
    }

    public func cancelSession() {
        sessionManager?.cancel()
    }

    public func isRecording() -> Bool {
        sessionManager?.currentState == .recording
    }

    public func getSessionState() throws -> AnyPublisher<SessionState, Never> {
        let manager = try requireInitialized()
        return manager.stateFlow
    }

    public func getAudioQuality() throws -> AnyPublisher<AudioQualityMetrics, Never> {
        let manager = try requireInitialized()
        return manager.audioQualityFlow
    }

    public func getVoiceActivity() throws -> AnyPublisher<VoiceActivityData, Never> {
        let manager = try requireInitialized()
        return manager.voiceActivityFlow
    }

    public func getUploadProgress(sessionId: String) throws -> AnyPublisher<UploadStage?, Never> {
        let dataManager = try requireDM()
        return dataManager.observeSession(sessionId)
            .map { record in
                guard let stage = record?.uploadStage else { return nil }
                return UploadStage(rawValue: stage)
            }
            .eraseToAnyPublisher()
    }

    public func getSessions() async throws -> [ScribeSession] {
        let dataManager = try requireDM()
        let sessions = try await dataManager.getAllSessions()
        return sessions.compactMap(Self.mapSession)
    }

    public func getSession(_ sessionId: String) async throws -> ScribeSession? {
        let dataManager = try requireDM()
        let session = try await dataManager.getSession(sessionId)
        return session.flatMap(Self.mapSession)
    }

    public func retrySession(_ sessionId: String, forceCommit: Bool = false) async throws -> TransactionResult {
        let transactionManager = try requireTxnManager()
        return await transactionManager.checkAndProgress(sessionId: sessionId, force: forceCommit)
    }

    public func getSessionOutput(_ sessionId: String) async -> Result<SessionResult, Error> {
        let api: ScribeAPIServiceProtocol
        do {
            api = try requireAPI()
        } catch {
            return .failure(error)
        }

        switch await api.getTransactionResult(sessionId) {
        case .success(let response, _):
            return .success(SessionManager.mapToSessionResult(sessionId: sessionId, response))
        case .serverError(_, let message):
            return .failure(ScribeException(code: .transcriptionFailed, message: message))
        case .networkError(let error), .unknownError(let error):
            return .failure(error)
        }
    }

    public func pollSessionResult(_ sessionId: String) async -> Result<SessionResult, Error> {
        do {
            _ = try requireAPI()
        } catch {
            return .failure(error)
        }

        guard let config else {
            return .failure(ScribeException(code: .invalidConfig, message: "SDK config unavailable"))
        }

        for _ in 0..<config.pollMaxRetries {
            let result = await getSessionOutput(sessionId)
            switch result {
            case .success(let sessionResult):
                return .success(sessionResult)
            case .failure:
                try? await Task.sleep(nanoseconds: UInt64(config.pollDelayMs) * 1_000_000)
            }
        }

        return .failure(ScribeException(code: .pollTimeout, message: "Result polling timed out"))
    }

    public func convertTransactionResult(_ sessionId: String, templateId: String) async -> Result<Bool, Error> {
        let api: ScribeAPIServiceProtocol
        do {
            api = try requireAPI()
        } catch {
            return .failure(error)
        }

        switch await api.convertTransactionResult(sessionId, templateId: templateId) {
        case .success:
            return .success(true)
        case .serverError(_, let message):
            return .failure(ScribeException(code: .unknown, message: message))
        case .networkError(let error), .unknownError(let error):
            return .failure(error)
        }
    }

    public func updateSessionResult(_ sessionId: String, updatedData: [SessionData]) async -> Result<Bool, Error> {
        let api: ScribeAPIServiceProtocol
        do {
            api = try requireAPI()
        } catch {
            return .failure(error)
        }

        let request = updatedData.map { UpdateSessionRequestItem(data: $0.data, templateId: $0.templateId) }
        switch await api.updateSession(sessionId, request) {
        case .success:
            return .success(true)
        case .serverError(_, let message):
            return .failure(ScribeException(code: .unknown, message: message))
        case .networkError(let error), .unknownError(let error):
            return .failure(error)
        }
    }

    public func getTemplates() async -> Result<[TemplateItem], Error> {
        let api: ScribeAPIServiceProtocol
        do {
            api = try requireAPI()
        } catch {
            return .failure(error)
        }

        switch await api.getTemplates() {
        case .success(let response, _):
            let items = response.data?.templates?.compactMap { dto -> TemplateItem? in
                guard let id = dto.id, let title = dto.title else { return nil }
                return TemplateItem(
                    isDefault: dto.isDefault ?? false,
                    desc: dto.desc,
                    id: id,
                    isFavorite: dto.isFavorite ?? false,
                    sectionIds: dto.sectionIds ?? [],
                    title: title
                )
            } ?? []
            return .success(items)

        case .serverError(_, let message):
            return .failure(ScribeException(code: .unknown, message: message))

        case .networkError(let error), .unknownError(let error):
            return .failure(error)
        }
    }

    public func updateTemplates(favouriteTemplates: [String]) async -> Result<Void, Error> {
        let api: ScribeAPIServiceProtocol
        do {
            api = try requireAPI()
        } catch {
            return .failure(error)
        }

        let request = UpdateTemplatesRequest(data: .init(myTemplates: favouriteTemplates))
        switch await api.updateTemplates(request) {
        case .success:
            return .success(())
        case .serverError(_, let message):
            return .failure(ScribeException(code: .unknown, message: message))
        case .networkError(let error), .unknownError(let error):
            return .failure(error)
        }
    }

    public func getUserConfigs() async -> Result<UserConfigs, Error> {
        let api: ScribeAPIServiceProtocol
        do {
            api = try requireAPI()
        } catch {
            return .failure(error)
        }

        switch await api.getUserConfig() {
        case .success(let response, _):
            guard let config = mapUserConfigs(response) else {
                return .failure(ScribeException(code: .unknown, message: "Invalid user config payload"))
            }
            return .success(config)

        case .serverError(_, let message):
            return .failure(ScribeException(code: .unknown, message: message))

        case .networkError(let error), .unknownError(let error):
            return .failure(error)
        }
    }

    public func updateUserConfigs(_ prefs: SelectedUserPreferences) async -> Result<Bool, Error> {
        let api: ScribeAPIServiceProtocol
        do {
            api = try requireAPI()
        } catch {
            return .failure(error)
        }

        let request = UpdateUserConfigRequest(
            data: .init(
                consultationMode: prefs.consultationMode?.id,
                inputLanguages: prefs.languages.map { .init(id: $0.id, name: $0.name) },
                modelType: prefs.modelType?.id,
                outputFormatTemplate: prefs.outputTemplates.map { .init(id: $0.id, name: $0.name, templateType: nil) }
            )
        )

        switch await api.updateUserConfig(request) {
        case .success:
            return .success(true)
        case .serverError(_, let message):
            return .failure(ScribeException(code: .unknown, message: message))
        case .networkError(let error), .unknownError(let error):
            return .failure(error)
        }
    }

    public func getHistory(count: Int? = nil) async throws -> [ScribeHistoryItem] {
        let apiService = try requireAPI()
        switch await apiService.getHistory(count: count) {
        case .success(let response, _):
            return response.data?.map { item in
                ScribeHistoryItem(
                    bId: item.bId,
                    createdAt: item.createdAt,
                    flavour: item.flavour,
                    mode: item.mode,
                    oid: item.oid,
                    processingStatus: item.processingStatus,
                    txnId: item.txnId,
                    userStatus: item.userStatus,
                    uuid: item.uuid,
                    version: item.version,
                    patientDetails: item.patientDetails.map {
                        ScribePatientInfo(
                            age: $0.age,
                            biologicalSex: $0.biologicalSex,
                            name: $0.name,
                            patientId: $0.patientId,
                            visitId: $0.visitId
                        )
                    }
                )
            } ?? []

        case .serverError, .networkError, .unknownError:
            return []
        }
    }

    public func getFullAudioFile() -> URL? {
        guard let path = sessionManager?.lastFullAudioPath,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    public func destroy() {
        sessionManager?.destroy()
        sessionManager = nil
        transactionManager = nil
        dataManager = nil
        networkClient = nil
        apiService = nil
        modelDownloader = nil
        config = nil
        isInitialized = false
        cancellables.removeAll()
    }

    private func requireInitialized() throws -> SessionManager {
        guard isInitialized, let manager = sessionManager else {
            throw notInitializedError()
        }
        return manager
    }

    private func requireDM() throws -> DataManager {
        guard isInitialized, let dataManager else {
            throw notInitializedError()
        }
        return dataManager
    }

    private func requireTxnManager() throws -> TransactionManager {
        guard isInitialized, let transactionManager else {
            throw notInitializedError()
        }
        return transactionManager
    }

    private func requireAPI() throws -> ScribeAPIServiceProtocol {
        guard isInitialized, let apiService else {
            throw notInitializedError()
        }
        return apiService
    }

    private func notInitializedError() -> ScribeError {
        ScribeError(
            code: .invalidConfig,
            message: "EkaScribe SDK not initialized. Call initialize() first."
        )
    }

    static func mapSession(_ session: SessionRecord) -> ScribeSession? {
        guard let stage = UploadStage(rawValue: session.uploadStage) else {
            return nil
        }
        return ScribeSession(
            sessionId: session.sessionId,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            state: session.state,
            chunkCount: session.chunkCount,
            uploadStage: stage
        )
    }

    func mapUserConfigs(_ response: GetConfigResponse) -> UserConfigs? {
        guard let data = response.data else { return nil }

        let consultationModes = ConsultationModeConfig(
            modes: data.consultationModes?.items?.compactMap {
                guard let id = $0.id, let name = $0.name else { return nil }
                return ConsultationMode(id: id, name: name, desc: $0.desc ?? "")
            } ?? [],
            maxSelection: data.consultationModes?.maxSelection ?? 1
        )

        let supportedLanguages = SupportedLanguagesConfig(
            languages: data.supportedLanguages?.items?.compactMap {
                guard let id = $0.id, let name = $0.name else { return nil }
                return SupportedLanguage(id: id, name: name)
            } ?? [],
            maxSelection: data.supportedLanguages?.maxSelection ?? 1
        )

        let outputTemplates = OutputTemplatesConfig(
            templates: data.outputTemplates?.items?.compactMap {
                guard let id = $0.id, let name = $0.name else { return nil }
                return ConfigOutputTemplate(id: id, name: name)
            } ?? [],
            maxSelection: data.outputTemplates?.maxSelection ?? 1
        )

        let modelConfigs = ModelConfigs(
            modelTypes: data.modelConfigs?.items?.compactMap {
                guard let id = $0.id, let name = $0.name else { return nil }
                return ModelType(id: id, name: name, desc: $0.desc ?? "")
            } ?? [],
            maxSelection: data.modelConfigs?.maxSelection ?? 1
        )

        let selected = SelectedUserPreferences(
            consultationMode: data.selectedUserPreferences?.consultationMode.flatMap {
                guard let id = $0.id, let name = $0.name else { return nil }
                return ConsultationMode(id: id, name: name, desc: $0.desc ?? "")
            },
            languages: data.selectedUserPreferences?.languages?.compactMap {
                guard let id = $0.id, let name = $0.name else { return nil }
                return SupportedLanguage(id: id, name: name)
            } ?? [],
            outputTemplates: data.selectedUserPreferences?.outputTemplates?.compactMap {
                guard let id = $0.id, let name = $0.name else { return nil }
                return ConfigOutputTemplate(id: id, name: name)
            } ?? [],
            modelType: data.selectedUserPreferences?.modelType.flatMap {
                guard let id = $0.id, let name = $0.name else { return nil }
                return ModelType(id: id, name: name, desc: $0.desc ?? "")
            }
        )

        return UserConfigs(
            consultationModes: consultationModes,
            supportedLanguages: supportedLanguages,
            outputTemplates: outputTemplates,
            selectedUserPreferences: selected,
            modelConfigs: modelConfigs
        )
    }
}
