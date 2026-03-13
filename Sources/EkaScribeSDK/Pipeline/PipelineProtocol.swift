import Combine
import Foundation

protocol PipelineProtocol: AnyObject {
    func start()
    func startCoroutines()
    func pause()
    func resume()
    func stop() async -> FullAudioResult?

    var audioFocusFlow: AnyPublisher<Bool, Never> { get }
    var audioQualityFlow: AnyPublisher<AudioQualityMetrics, Never> { get }
    var voiceActivityFlow: AnyPublisher<VoiceActivityData, Never> { get }
}

protocol PipelineCreating {
    func create(
        sessionId: String,
        folderName: String,
        bid: String,
        onEvent: ((SessionEventName, EventType, String, [String: String]) -> Void)?
    ) -> PipelineProtocol
}
