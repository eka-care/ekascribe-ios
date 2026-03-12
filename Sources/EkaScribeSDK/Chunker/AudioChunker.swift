import Combine
import Foundation

protocol AudioChunker {
    func feed(_ frame: AudioFrame) -> AudioChunk?
    func flush() -> AudioChunk?
    func setLatestQuality(_ quality: AudioQuality?)
    var activityFlow: AnyPublisher<VoiceActivityData, Never> { get }
    func release()
}
