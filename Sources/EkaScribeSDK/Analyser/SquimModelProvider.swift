import Foundation

final class SquimModelProvider {
    private let modelPath: String
    private let logger: Logger
    private(set) var isLoaded = false
    private let analysisChunkSize = 16_000

    init(modelPath: String, logger: Logger) {
        self.modelPath = modelPath
        self.logger = logger
    }

    func load() {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            logger.error("Analyser", "SQUIM model not found at path: \(modelPath)")
            isLoaded = false
            return
        }
        isLoaded = true
    }

    func analyze(frames: [AudioFrame]) -> AudioQuality? {
        guard isLoaded, !frames.isEmpty else { return nil }
        let pcm = frames.flatMap { $0.pcm }
        guard !pcm.isEmpty else { return nil }

        // Placeholder estimator until ONNX objective model integration is wired.
        let rms = sqrt(pcm.reduce(Float(0)) { partial, sample in
            let x = Float(sample) / 32767.0
            return partial + (x * x)
        } / Float(max(1, pcm.count)))

        let stoi = min(1.0, max(0.0, rms * 2.0))
        let pesq = min(4.5, max(-0.5, Float(-0.5 + (rms * 5.0))))
        let siSDR = max(-20.0, min(30.0, (rms * 50.0) - 20.0))
        let overall = min(1.0, max(0.0, (stoi + ((pesq + 0.5) / 5.0)) / 2.0))

        return AudioQuality(stoi: stoi, pesq: pesq, siSDR: siSDR, overallScore: overall)
    }

    func unload() {
        isLoaded = false
    }
}
