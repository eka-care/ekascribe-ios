import Foundation

public enum AnalyserState: Sendable {
    case disabled
    case idle
    case downloading(progressPercent: Int)
    case ready(modelPath: String)
    case failed(error: String)
}
