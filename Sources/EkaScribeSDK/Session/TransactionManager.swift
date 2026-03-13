import Foundation

final class TransactionManager: TransactionManaging {
    private let apiService: ScribeAPIServiceProtocol
    private let dataManager: DataManager
    private let chunkUploader: ChunkUploader
    private let bucketName: String
    private let maxUploadRetries: Int
    private let pollMaxRetries: Int
    private let pollDelayMs: Int
    private let logger: Logger

    init(
        apiService: ScribeAPIServiceProtocol,
        dataManager: DataManager,
        chunkUploader: ChunkUploader,
        bucketName: String,
        maxUploadRetries: Int,
        pollMaxRetries: Int,
        pollDelayMs: Int,
        logger: Logger
    ) {
        self.apiService = apiService
        self.dataManager = dataManager
        self.chunkUploader = chunkUploader
        self.bucketName = bucketName
        self.maxUploadRetries = maxUploadRetries
        self.pollMaxRetries = pollMaxRetries
        self.pollDelayMs = pollDelayMs
        self.logger = logger
    }

    func initTransaction(sessionId: String, sessionConfig: SessionConfig, folderName: String) async -> TransactionResult {
        let s3Url = "s3://\(bucketName)/\(folderName)/\(sessionId)"
        let request = InitTransactionRequest(
            inputLanguage: sessionConfig.languages,
            mode: sessionConfig.mode,
            outputFormatTemplate: sessionConfig.outputTemplates?.map {
                OutputFormatTemplateDTO(templateId: $0.templateId, type: $0.templateType, name: $0.templateName)
            },
            s3Url: s3Url,
            section: sessionConfig.section,
            speciality: sessionConfig.speciality,
            modelType: sessionConfig.modelType,
            patientDetails: sessionConfig.patientDetails.map {
                PatientDetailsDTO(
                    age: $0.age,
                    biologicalSex: $0.biologicalSex,
                    name: $0.name,
                    patientId: $0.patientId,
                    visitId: $0.visitId
                )
            }
        )

        switch await apiService.initTransaction(sessionId, request) {
        case .success(let response, _):
            let bid = response.bId ?? ""
            try? await dataManager.updateStageAndBid(sessionId, TransactionStage.stop.rawValue, bid)
            return .success(folderName: folderName, bid: bid)

        case .serverError(_, let message):
            return .error(message: message)

        case .networkError(let error):
            return .error(message: "Network error: \(error.localizedDescription)")

        case .unknownError(let error):
            return .error(message: "Unknown error: \(error.localizedDescription)")
        }
    }

    func stopTransaction(sessionId: String) async -> TransactionResult {
        let chunks = try? await dataManager.getUploadedChunks(sessionId: sessionId)
        let audioFiles = chunks?.map { $0.fileName } ?? []
        let chunkInfo = chunks?.map {
            [$0.fileName: ChunkDataDTO(startTime: Double($0.startTimeMs) / 1000.0, endTime: Double($0.endTimeMs) / 1000.0)]
        } ?? []

        let request = StopTransactionRequest(audioFiles: audioFiles, chunkInfo: chunkInfo)
        switch await apiService.stopTransaction(sessionId, request) {
        case .success:
            try? await dataManager.updateUploadStage(sessionId, TransactionStage.commit.rawValue)
            return .success()

        case .serverError(_, let message):
            return .error(message: message)

        case .networkError(let error):
            return .error(message: "Network error: \(error.localizedDescription)")

        case .unknownError(let error):
            return .error(message: "Unknown error: \(error.localizedDescription)")
        }
    }

    func commitTransaction(sessionId: String) async -> TransactionResult {
        let chunks = try? await dataManager.getUploadedChunks(sessionId: sessionId)
        let audioFiles = chunks?.map { $0.fileName } ?? []
        let request = StopTransactionRequest(audioFiles: audioFiles, chunkInfo: [])

        switch await apiService.commitTransaction(sessionId, request) {
        case .success:
            try? await dataManager.updateUploadStage(sessionId, TransactionStage.analyzing.rawValue)
            return .success()

        case .serverError(_, let message):
            return .error(message: message)

        case .networkError(let error):
            return .error(message: "Network error: \(error.localizedDescription)")

        case .unknownError(let error):
            return .error(message: "Unknown error: \(error.localizedDescription)")
        }
    }

    func pollResult(sessionId: String) async -> TransactionPollResult {
        let successStates: Set<ResultStatus> = [.success, .partialCompleted]
        let failureStates: Set<ResultStatus> = [.failure]

        for _ in 0..<pollMaxRetries {
            switch await apiService.getTransactionResult(sessionId) {
            case .success(let response, let statusCode):
                if statusCode == 202 {
                    try? await Task.sleep(nanoseconds: UInt64(pollDelayMs) * 1_000_000)
                    continue
                }

                let statuses = response.data?.output?.compactMap { $0?.status } ?? []

                if statuses.contains(where: { successStates.contains($0) }) {
                    try? await dataManager.updateUploadStage(sessionId, TransactionStage.completed.rawValue)
                    return .success(result: response)
                }

                if !statuses.isEmpty && statuses.allSatisfy({ failureStates.contains($0) }) {
                    try? await dataManager.updateUploadStage(sessionId, TransactionStage.failure.rawValue)
                    return .failed(error: "Transcription processing failed")
                }

                try? await Task.sleep(nanoseconds: UInt64(pollDelayMs) * 1_000_000)

            case .serverError(_, let message):
                logger.warn("Txn", "Poll server error: \(message)")
                try? await Task.sleep(nanoseconds: UInt64(pollDelayMs) * 1_000_000)

            case .networkError(let error):
                logger.warn("Txn", "Poll network error", error)
                try? await Task.sleep(nanoseconds: UInt64(pollDelayMs) * 1_000_000)

            case .unknownError(let error):
                logger.warn("Txn", "Poll unknown error", error)
                try? await Task.sleep(nanoseconds: UInt64(pollDelayMs) * 1_000_000)
            }
        }

        return .timeout
    }

    func retryFailedUploads(sessionId: String) async -> Bool {
        await chunkUploader.clearCache()

        guard let allChunks = try? await dataManager.getAllChunks(sessionId: sessionId) else {
            return false
        }

        let toRetry = allChunks.filter { $0.uploadState != UploadState.success.rawValue }
        guard !toRetry.isEmpty else {
            return (try? await dataManager.areAllChunksUploaded(sessionId: sessionId)) ?? false
        }

        guard let session = try? await dataManager.getSession(sessionId) else {
            return false
        }

        let folderName = session.folderName ?? ""
        let bid = session.bid ?? ""

        for chunk in toRetry {
            let file = URL(fileURLWithPath: chunk.filePath)
            guard FileManager.default.fileExists(atPath: chunk.filePath) else {
                logger.warn("Txn", "Chunk file missing for retry: \(chunk.filePath)")
                continue
            }

            try? await dataManager.markInProgress(chunk.chunkId)

            let metadata = UploadMetadata(
                chunkId: chunk.chunkId,
                sessionId: chunk.sessionId,
                chunkIndex: chunk.chunkIndex,
                fileName: chunk.fileName,
                folderName: folderName,
                bid: bid
            )

            switch await chunkUploader.upload(file: file, metadata: metadata) {
            case .success:
                try? await dataManager.markUploaded(chunk.chunkId)
                deleteFile(file, logger: logger)

            case .failure:
                try? await dataManager.markFailed(chunk.chunkId)
            }
        }

        return (try? await dataManager.areAllChunksUploaded(sessionId: sessionId)) ?? false
    }

    func checkAndProgress(sessionId: String, sessionConfig: SessionConfig? = nil, force: Bool = false) async -> TransactionResult {
        guard let session = try? await dataManager.getSession(sessionId) else {
            return .error(message: "Session not found")
        }

        guard let stage = TransactionStage(rawValue: session.uploadStage) else {
            return .error(message: "Unknown stage")
        }

        switch stage {
        case .initialize:
            guard let sessionConfig else {
                return .error(message: "No session config for recovery")
            }
            let folderName = session.folderName ?? Self.defaultFolderName()
            let result = await initTransaction(sessionId: sessionId, sessionConfig: sessionConfig, folderName: folderName)
            if case .success = result {
                return await checkAndProgress(sessionId: sessionId, sessionConfig: sessionConfig, force: force)
            }
            return result

        case .stop:
            let allUploaded = await retryFailedUploads(sessionId: sessionId)
            if !allUploaded && !force {
                return .error(message: "Not all chunks uploaded. Use forceCommit=true.")
            }
            let result = await stopTransaction(sessionId: sessionId)
            if case .success = result {
                return await checkAndProgress(sessionId: sessionId, sessionConfig: sessionConfig, force: force)
            }
            return result

        case .commit:
            let result = await commitTransaction(sessionId: sessionId)
            if case .success = result {
                return await checkAndProgress(sessionId: sessionId, sessionConfig: sessionConfig, force: force)
            }
            return result

        case .analyzing:
            switch await pollResult(sessionId: sessionId) {
            case .success:
                try? await dataManager.updateSessionState(sessionId, SessionState.completed.rawValue)
                return .success()
            case .failed(let error):
                return .error(message: error)
            case .timeout:
                return .error(message: "Poll timeout")
            }

        case .completed, .failure, .error:
            return .success()
        }
    }

    static func defaultFolderName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: Date())
    }
}
