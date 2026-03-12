import Combine
import Foundation

final class NoOpAudioAnalyser: AudioAnalyser {
    func submitFrame(_ frame: AudioFrame) {}

    var qualityFlow: AnyPublisher<AudioQuality, Never> {
        Empty().eraseToAnyPublisher()
    }

    func release() {}
}
