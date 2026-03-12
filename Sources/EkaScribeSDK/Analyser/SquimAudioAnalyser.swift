import Combine
import Foundation

final class SquimAudioAnalyser: AudioAnalyser, @unchecked Sendable {
    private let modelProvider: SquimModelProvider
    private let analysisDurationMs: Int64 = 3000
    private let logger: Logger
    private var accumulatedFrames: [AudioFrame] = []
    private var lastAnalysisTime: Int64 = 0
    private let qualitySubject = PassthroughSubject<AudioQuality, Never>()
    private let lock = NSLock()

    init(modelProvider: SquimModelProvider, logger: Logger) {
        self.modelProvider = modelProvider
        self.logger = logger
    }

    var qualityFlow: AnyPublisher<AudioQuality, Never> {
        qualitySubject.eraseToAnyPublisher()
    }

    func submitFrame(_ frame: AudioFrame) {
        guard modelProvider.isLoaded else { return }

        lock.lock()
        accumulatedFrames.append(frame)
        let elapsed = frame.timestampMs - lastAnalysisTime
        guard elapsed >= analysisDurationMs else {
            lock.unlock()
            return
        }
        let frames = accumulatedFrames
        accumulatedFrames = []
        lastAnalysisTime = frame.timestampMs
        lock.unlock()

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            if let quality = self.modelProvider.analyze(frames: frames) {
                self.qualitySubject.send(quality)
            } else {
                self.logger.warn("Analyser", "No quality output from model")
            }
        }
    }

    func release() {
        modelProvider.unload()
    }
}
