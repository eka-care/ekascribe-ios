import Combine
import Foundation

protocol AudioAnalyser {
    func submitFrame(_ frame: AudioFrame)
    var qualityFlow: AnyPublisher<AudioQuality, Never> { get }
    func release()
}
