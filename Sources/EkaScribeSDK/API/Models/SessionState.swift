import Foundation

public enum SessionState: String, Codable, Sendable {
    case idle
    case starting
    case recording
    case paused
    case stopping
    case processing
    case completed
    case error

    public func canTransition(to target: SessionState) -> Bool {
        switch self {
        case .idle:
            return target == .starting
        case .starting:
            return [.recording, .error].contains(target)
        case .recording:
            return [.paused, .stopping, .idle, .error].contains(target)
        case .paused:
            return [.recording, .stopping, .idle].contains(target)
        case .stopping:
            return [.processing, .completed, .error].contains(target)
        case .processing:
            return [.completed, .error].contains(target)
        case .completed:
            return target == .idle
        case .error:
            return target == .idle
        }
    }
}
