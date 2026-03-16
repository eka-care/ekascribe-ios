import Foundation

/// Audio frame size options (number of samples per frame).
public enum FrameSize: Sendable {
    case samples160
    case samples320
    case samples480
    case samples512

    /// The integer value (number of samples).
    public var intValue: Int {
        switch self {
        case .samples160: return 160
        case .samples320: return 320
        case .samples480: return 480
        case .samples512: return 512
        }
    }
}
