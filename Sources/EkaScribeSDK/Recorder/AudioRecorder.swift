import Foundation

protocol AudioRecorder {
    func start()
    func stop()
    func pause()
    func resume()

    var onFrame: ((AudioFrame) -> Void)? { get set }
    var onAudioFocusChanged: ((Bool) -> Void)? { get set }
}
