import Foundation

/// Fire-and-forget chunk upload consumer with bounded concurrency.
///
/// The producer (Pipeline's persistence loop) calls `submit(...)` which returns
/// immediately after spawning a background Task. The Task waits on a semaphore
/// (capped at `PipelineLimits.maxConcurrentUploads`) before actually uploading,
/// so a slow upload can never stall chunk creation — only other uploads queue.
///
/// At shutdown, `drain()` awaits every inflight Task before returning so that
/// SessionManager's `stopTransaction` still observes a settled upload state.
final class ChunkUploadCoordinator: @unchecked Sendable {
    private let uploader: ChunkUploader
    private let dataManager: DataManager
    private let semaphore: AsyncSemaphore
    private let logger: Logger
    private let onEvent: ((SessionEventName, EventType, String, [String: String]) -> Void)?

    private let lock = NSLock()
    private var inflight: [Task<Void, Never>] = []

    init(
        uploader: ChunkUploader,
        dataManager: DataManager,
        logger: Logger,
        onEvent: ((SessionEventName, EventType, String, [String: String]) -> Void)?
    ) {
        self.uploader = uploader
        self.dataManager = dataManager
        self.semaphore = AsyncSemaphore(value: PipelineLimits.maxConcurrentUploads)
        self.logger = logger
        self.onEvent = onEvent
    }

    /// Returns immediately. The upload happens on a detached Task that first
    /// waits on the semaphore, then uploads, updates DB state, and emits events.
    func submit(chunkId: String, chunkIndex: Int, file: URL, metadata: UploadMetadata) {
        let uploader = self.uploader
        let dataManager = self.dataManager
        let semaphore = self.semaphore
        let logger = self.logger
        let onEvent = self.onEvent

        let task = Task {
            await semaphore.wait()
            defer { Task { await semaphore.signal() } }

            try? await dataManager.markInProgress(chunkId)

            onEvent?(.chunkUploadStarted, .info, "Chunk upload started", [
                "chunkId": chunkId,
                "chunkIndex": "\(chunkIndex)"
            ])

            switch await uploader.upload(file: file, metadata: metadata) {
            case .success:
                try? await dataManager.markUploaded(chunkId)
                deleteFile(file, logger: logger)
                onEvent?(.chunkUploaded, .success, "Chunk uploaded", [
                    "chunkId": chunkId,
                    "chunkIndex": "\(chunkIndex)"
                ])

            case .failure(let error, _):
                try? await dataManager.markFailed(chunkId)
                onEvent?(.chunkUploadFailed, .error, "Chunk upload failed: \(error)", [
                    "chunkId": chunkId,
                    "error": error
                ])
            }
        }

        lock.lock()
        inflight.append(task)
        lock.unlock()
    }

    /// Awaits all inflight uploads. Called by Pipeline.stop() before full-audio
    /// generation so the post-stop transaction observes settled DB state.
    func drain() async {
        lock.lock()
        let tasks = inflight
        inflight.removeAll()
        lock.unlock()

        for task in tasks {
            await task.value
        }
    }

    /// Best-effort cancellation of inflight uploads. Called by Pipeline.cancel().
    /// Cancelled uploads leave their DB row in .inProgress/.failed; the retry
    /// sweep picks them up.
    func cancelAll() {
        lock.lock()
        let tasks = inflight
        inflight.removeAll()
        lock.unlock()

        for task in tasks { task.cancel() }
    }
}
