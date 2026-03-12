import Foundation

final class FrameProducer: @unchecked Sendable {
    private let preBuffer: PreBuffer
    private let continuation: AsyncStream<AudioFrame>.Continuation
    private let logger: Logger
    private var task: Task<Void, Never>?
    private var stopped = false

    init(preBuffer: PreBuffer, continuation: AsyncStream<AudioFrame>.Continuation, logger: Logger) {
        self.preBuffer = preBuffer
        self.continuation = continuation
        self.logger = logger
    }

    func start() {
        task = Task {
            while !stopped && !Task.isCancelled {
                let frames = preBuffer.drain()
                for frame in frames {
                    continuation.yield(frame)
                }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }

            let remaining = preBuffer.drain()
            for frame in remaining {
                continuation.yield(frame)
            }

            logger.debug("FrameProducer", "Frame stream finished")
            continuation.finish()
        }
    }

    func stopAndDrain() async {
        stopped = true
        await task?.value
    }
}
