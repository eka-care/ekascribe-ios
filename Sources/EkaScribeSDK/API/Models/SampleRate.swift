import Foundation

/// Audio sample rate options supported by the SDK.
public enum SampleRate: Sendable {
    case hz8000
    case hz16000
    case hz32000
    case hz48000

    /// The integer value in Hz.
    public var intValue: Int {
        switch self {
        case .hz8000:  return 8000
        case .hz16000: return 16000
        case .hz32000: return 32000
        case .hz48000: return 48000
        }
    }
}
