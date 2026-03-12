import Combine
import Foundation

final class ModelDownloader: @unchecked Sendable {
    private let filesDir: URL
    private let logger: Logger
    private let modelURL = URL(string: "https://github.com/divyesh11/squim-models/releases/download/v1.0.6/squim_objective_for_android.onnx")!
    private var eTagPath: URL {
        filesDir.appendingPathComponent("models/squim_objective.etag")
    }

    @Published private(set) var state: AnalyserState = .idle

    init(filesDir: URL, logger: Logger) {
        self.filesDir = filesDir
        self.logger = logger
    }

    var modelPath: String? {
        let file = filesDir.appendingPathComponent("models/squim_objective.onnx")
        return file.exists && file.fileSize > 0 ? file.path : nil
    }

    func downloadIfNeeded() async {
        let target = filesDir.appendingPathComponent("models/squim_objective.onnx")
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

            if target.exists && target.fileSize > 0 {
                state = .ready(modelPath: target.path)
                return
            }

            state = .downloading(progressPercent: 0)
            var request = URLRequest(url: modelURL)
            if let etag = try? String(contentsOf: eTagPath, encoding: .utf8), !etag.isEmpty {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            if statusCode == 304, target.exists {
                state = .ready(modelPath: target.path)
                return
            }

            guard (200..<300).contains(statusCode), !data.isEmpty else {
                state = .failed(error: "Model download failed with status: \(statusCode)")
                return
            }

            try data.write(to: target, options: .atomic)
            if let etag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag") {
                try? etag.write(to: eTagPath, atomically: true, encoding: .utf8)
            }
            state = .ready(modelPath: target.path)
        } catch {
            logger.error("ModelDownloader", "Download failed", error)
            state = .failed(error: error.localizedDescription)
        }
    }
}
