import Combine
import Foundation

final class Pipeline: PipelineProtocol, @unchecked Sendable {
    private var recorder: AudioRecorder
    private let preBuffer: PreBuffer
    private let frameProducer: FrameProducer
    private let analyser: AudioAnalyser
    private let chunker: AudioChunker
    private let dataManager: DataManager
    private let encoder: AudioEncoder
    private let chunkUploader: ChunkUploader
    private let sessionId: String
    private let folderName: String
    private let bid: String
    private let outputDir: URL
    private let timeProvider: TimeProvider
    private let logger: Logger
    private let onEvent: ((SessionEventName, EventType, String, [String: String]) -> Void)?

    private let frameStream: AsyncStream<AudioFrame>
    private let frameContinuation: AsyncStream<AudioFrame>.Continuation
    private let chunkStream: AsyncStream<AudioChunk>
    private let chunkContinuation: AsyncStream<AudioChunk>.Continuation

    private var chunkingTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var qualityForwardTask: Task<Void, Never>?

    private let rawPcmFilePath: String
    private var rawPcmFileHandle: FileHandle?
    private var recordedSampleRate: Int = 16_000

    private let audioFocusSubject = CurrentValueSubject<Bool, Never>(true)
    var audioFocusFlow: AnyPublisher<Bool, Never> { audioFocusSubject.eraseToAnyPublisher() }

    var audioQualityFlow: AnyPublisher<AudioQualityMetrics, Never> {
        analyser.qualityFlow
            .map { $0.toMetrics() }
            .eraseToAnyPublisher()
    }

    var voiceActivityFlow: AnyPublisher<VoiceActivityData, Never> {
        chunker.activityFlow
    }

    init(
        recorder: AudioRecorder,
        preBuffer: PreBuffer,
        frameProducer: FrameProducer,
        analyser: AudioAnalyser,
        chunker: AudioChunker,
        dataManager: DataManager,
        encoder: AudioEncoder,
        chunkUploader: ChunkUploader,
        sessionId: String,
        folderName: String,
        bid: String,
        outputDir: URL,
        timeProvider: TimeProvider,
        logger: Logger,
        onEvent: ((SessionEventName, EventType, String, [String: String]) -> Void)?,
        frameStream: AsyncStream<AudioFrame>,
        frameContinuation: AsyncStream<AudioFrame>.Continuation,
        chunkStream: AsyncStream<AudioChunk>,
        chunkContinuation: AsyncStream<AudioChunk>.Continuation
    ) {
        self.recorder = recorder
        self.preBuffer = preBuffer
        self.frameProducer = frameProducer
        self.analyser = analyser
        self.chunker = chunker
        self.dataManager = dataManager
        self.encoder = encoder
        self.chunkUploader = chunkUploader
        self.sessionId = sessionId
        self.folderName = folderName
        self.bid = bid
        self.outputDir = outputDir
        self.timeProvider = timeProvider
        self.logger = logger
        self.onEvent = onEvent
        self.frameStream = frameStream
        self.frameContinuation = frameContinuation
        self.chunkStream = chunkStream
        self.chunkContinuation = chunkContinuation
        self.rawPcmFilePath = outputDir.appendingPathComponent("\(sessionId)_raw.pcm").path
    }

    func start() {
        recorder.onFrame = { [weak self] frame in
            guard let self else { return }
            if !preBuffer.write(frame) { //guard
                logger.warn("Pipeline", "PreBuffer full, frame dropped: \(frame.frameIndex)")
            }
        }

        recorder.onAudioFocusChanged = { [weak self] hasFocus in
            self?.audioFocusSubject.send(hasFocus)
        }

        recorder.start()
    }

    func startCoroutines() {
        // Create raw PCM file for streaming full audio to disk
        FileManager.default.createFile(atPath: rawPcmFilePath, contents: nil)
        rawPcmFileHandle = FileHandle(forWritingAtPath: rawPcmFilePath)

        frameProducer.start()
        startChunkingTask()
        startPersistenceTask()
        startQualityForwardTask()
    }

    func pause() {
        recorder.pause()
    }

    func resume() {
        recorder.resume()
    }

    func stop() async -> FullAudioResult? {
        recorder.stop()
        await frameProducer.stopAndDrain()
        await chunkingTask?.value
        await persistenceTask?.value
        qualityForwardTask?.cancel()

        // Close the raw PCM file before encoding
        rawPcmFileHandle?.closeFile()
        rawPcmFileHandle = nil

        let result = await generateFullAudio()

        analyser.release()
        chunker.release()
        preBuffer.clear()
        frameContinuation.finish()

        logger.info("Pipeline", "Pipeline stopped for session: \(sessionId)")
        return result
    }

    func cancel() {
        recorder.stop()

        // Finish continuations to unblock `for await` loops
        frameContinuation.finish()
        chunkContinuation.finish()

        // Cancel all tasks
        chunkingTask?.cancel()
        persistenceTask?.cancel()
        qualityForwardTask?.cancel()

        // Close file handle
        rawPcmFileHandle?.closeFile()
        rawPcmFileHandle = nil

        // Release resources
        analyser.release()
        chunker.release()
        preBuffer.clear()

        logger.info("Pipeline", "Pipeline cancelled for session: \(sessionId)")
    }

    private func startChunkingTask() {
        chunkingTask = Task { [weak self] in
            guard let self else { return }
            for await frame in self.frameStream {
                guard !Task.isCancelled else { break }
                // Stream PCM to disk instead of accumulating in memory
                if let handle = self.rawPcmFileHandle {
                    self.recordedSampleRate = frame.sampleRate
                    frame.pcm.withUnsafeBufferPointer { ptr in
                        let data = Data(buffer: ptr)
                        handle.write(data)
                    }
                }
                self.analyser.submitFrame(frame)
                if let chunk = self.chunker.feed(frame) {
                    self.chunkContinuation.yield(chunk)
                }
            }

            if !Task.isCancelled, let lastChunk = self.chunker.flush() {
                self.chunkContinuation.yield(lastChunk)
            }
            self.chunkContinuation.finish()
        }
    }

    private func startPersistenceTask() {
        persistenceTask = Task { [weak self] in
            guard let self else { return }
            for await chunk in chunkStream {
                guard !Task.isCancelled else { break }
                do {
                    let outputPath = outputDir.appendingPathComponent("\(sessionId)_\(chunk.index + 1).m4a").path
                    let sampleRate = chunk.frames.first?.sampleRate ?? 16_000
                    let encoded = try await encoder.encode(frames: chunk.frames, sampleRate: sampleRate, outputPath: outputPath)

                    let fileName = "\(chunk.index + 1).\(encoded.format.fileExtension)"

                    let entity = AudioChunkRecord(
                        chunkId: chunk.chunkId,
                        sessionId: chunk.sessionId,
                        chunkIndex: chunk.index,
                        filePath: encoded.filePath,
                        fileName: fileName,
                        startTimeMs: chunk.startTimeMs,
                        endTimeMs: chunk.endTimeMs,
                        durationMs: encoded.durationMs,
                        uploadState: UploadState.pending.rawValue,
                        retryCount: 0,
                        qualityScore: chunk.quality?.overallScore,
                        createdAt: self.timeProvider.nowMillis()
                    )

                    try await self.dataManager.saveChunk(entity)
                    try await self.dataManager.markInProgress(chunk.chunkId)

                    let file = URL(fileURLWithPath: encoded.filePath)
                    let metadata = UploadMetadata(
                        chunkId: chunk.chunkId,
                        sessionId: chunk.sessionId,
                        chunkIndex: chunk.index,
                        fileName: fileName,
                        folderName: self.folderName,
                        bid: self.bid,
                        mimeType: encoded.format.mimeType
                    )

                    switch await self.chunkUploader.upload(file: file, metadata: metadata) {
                    case .success:
                        try await self.dataManager.markUploaded(chunk.chunkId)
                        deleteFile(file, logger: self.logger)
                        self.onEvent?(.chunkUploaded, .success, "Chunk uploaded", [
                            "chunkId": chunk.chunkId,
                            "chunkIndex": "\(chunk.index)"
                        ])

                    case .failure(let error, _):
                        try await self.dataManager.markFailed(chunk.chunkId)
                        self.onEvent?(.chunkUploadFailed, .error, "Chunk upload failed: \(error)", [
                            "chunkId": chunk.chunkId,
                            "error": error
                        ])
                    }
                } catch {
                    self.logger.error("Pipeline", "Failed to process chunk: \(chunk.chunkId)", error)
                    self.onEvent?(.chunkProcessingFailed, .error, "Chunk processing failed: \(error.localizedDescription)", [
                        "chunkId": chunk.chunkId
                    ])
                }
            }
        }
    }

    private func startQualityForwardTask() {
        qualityForwardTask = Task { [weak self] in
            guard let self else { return }
            for await quality in analyser.qualityFlow.values {
                chunker.setLatestQuality(quality)
            }
        }
    }

    private func generateFullAudio() async -> FullAudioResult? {
        guard FileManager.default.fileExists(atPath: rawPcmFilePath) else { return nil }

        // Check raw PCM file is not empty
        let pcmAttrs = try? FileManager.default.attributesOfItem(atPath: rawPcmFilePath)
        let pcmSize = (pcmAttrs?[.size] as? Int) ?? 0
        guard pcmSize > 0 else {
            try? FileManager.default.removeItem(atPath: rawPcmFilePath)
            return nil
        }

        let basePath = outputDir.appendingPathComponent("\(sessionId)_full_audio.m4a").path
        let encoded: EncodedChunk
        do {
            encoded = try await encoder.encodeFromFile(pcmFilePath: rawPcmFilePath, sampleRate: recordedSampleRate, outputPath: basePath)
        } catch {
            logger.error("Pipeline", "Failed to encode full audio", error)
            onEvent?(.fullAudioGenerationFailed, .error, "Full audio encoding failed", [:])
            try? FileManager.default.removeItem(atPath: rawPcmFilePath)
            return nil
        }

        // Clean up raw PCM file — no longer needed
        try? FileManager.default.removeItem(atPath: rawPcmFilePath)

        guard encoded.sizeBytes > 0 else {
            logger.error("Pipeline", "Full audio encoded file is empty")
            onEvent?(.fullAudioGenerationFailed, .error, "Full audio file is empty", [:])
            return nil
        }

        // Rename with trailing _ so backend skips analysis
        let renamedPath = encoded.filePath + "_"
        do {
            if FileManager.default.fileExists(atPath: renamedPath) {
                try FileManager.default.removeItem(atPath: renamedPath)
            }
            try FileManager.default.moveItem(atPath: encoded.filePath, toPath: renamedPath)
            onEvent?(.fullAudioGenerated, .success, "Full audio generated", ["filePath": renamedPath])
            return FullAudioResult(filePath: renamedPath, sessionId: sessionId, folderName: folderName, bid: bid)
        } catch {
            logger.error("Pipeline", "Failed to rename full audio file", error)
            onEvent?(.fullAudioGenerated, .success, "Full audio generated", ["filePath": encoded.filePath])
            return FullAudioResult(filePath: encoded.filePath, sessionId: sessionId, folderName: folderName, bid: bid)
        }
    }
}

extension Pipeline {
    final class Factory: PipelineCreating {
        private let config: EkaScribeConfig
        private let dataManager: DataManager
        private let encoder: AudioEncoder
        private let chunkUploader: ChunkUploader
        private let modelDownloader: ModelDownloader
        private let outputDir: URL
        private let timeProvider: TimeProvider
        private let logger: Logger

        init(
            config: EkaScribeConfig,
            dataManager: DataManager,
            encoder: AudioEncoder,
            chunkUploader: ChunkUploader,
            modelDownloader: ModelDownloader,
            outputDir: URL,
            timeProvider: TimeProvider,
            logger: Logger
        ) {
            self.config = config
            self.dataManager = dataManager
            self.encoder = encoder
            self.chunkUploader = chunkUploader
            self.modelDownloader = modelDownloader
            self.outputDir = outputDir
            self.timeProvider = timeProvider
            self.logger = logger
        }

        func create(
            sessionId: String,
            folderName: String,
            bid: String,
            onEvent: ((SessionEventName, EventType, String, [String: String]) -> Void)? = nil
        ) -> PipelineProtocol {
            let pipelineConfig = PipelineConfig(enableAnalyser: config.enableAnalyser)
            let recorderConfig = RecorderConfig(sampleRate: config.sampleRate.intValue, frameSize: config.frameSize.intValue)
            let recorder = IOSAudioRecorder(config: recorderConfig, logger: logger)

            let preBuffer = PreBuffer(capacity: pipelineConfig.preBufferCapacity)
            let framePair = AsyncStream<AudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(pipelineConfig.frameChannelCapacity))
            let chunkPair = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(pipelineConfig.chunkChannelCapacity))

            let frameProducer = FrameProducer(preBuffer: preBuffer, continuation: framePair.continuation, logger: logger)

            let analyser: AudioAnalyser
            if pipelineConfig.enableAnalyser, let modelPath = modelDownloader.modelPath {
                let provider = SquimModelProvider(modelPath: modelPath, logger: logger)
                provider.load()
                analyser = SquimAudioAnalyser(modelProvider: provider, logger: logger)
            } else {
                analyser = NoOpAudioAnalyser()
            }

            let vadProvider = LibfvadProvider(sampleRate: config.sampleRate.intValue, frameSize: config.frameSize.intValue, logger: logger)
            vadProvider.load()

            let chunkConfig = ChunkConfig(
                preferredDurationSec: config.preferredChunkDurationSec,
                desperationDurationSec: config.desperationChunkDurationSec,
                maxDurationSec: config.maxChunkDurationSec,
                overlapDurationSec: config.overlapDurationSec
            )

            let chunker = VadAudioChunker(
                vadProvider: vadProvider,
                config: chunkConfig,
                sessionId: sessionId,
                sampleRate: config.sampleRate.intValue,
                logger: logger
            )

            let pipeline = Pipeline(
                recorder: recorder,
                preBuffer: preBuffer,
                frameProducer: frameProducer,
                analyser: analyser,
                chunker: chunker,
                dataManager: dataManager,
                encoder: encoder,
                chunkUploader: chunkUploader,
                sessionId: sessionId,
                folderName: folderName,
                bid: bid,
                outputDir: outputDir,
                timeProvider: timeProvider,
                logger: logger,
                onEvent: onEvent,
                frameStream: framePair.stream,
                frameContinuation: framePair.continuation,
                chunkStream: chunkPair.stream,
                chunkContinuation: chunkPair.continuation
            )
            pipeline.startCoroutines()
            return pipeline
        }
    }
}
