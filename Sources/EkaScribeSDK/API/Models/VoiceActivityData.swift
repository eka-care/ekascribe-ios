import Foundation

public struct VoiceActivityData: Sendable {
    public let isSpeech: Bool
    public let amplitude: Float
    public let timestampMs: Int

    public init(isSpeech: Bool, amplitude: Float, timestampMs: Int) {
        self.isSpeech = isSpeech
        self.amplitude = amplitude
        self.timestampMs = timestampMs
    }
}
