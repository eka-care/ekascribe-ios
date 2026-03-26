import Foundation

protocol AudioRecorder {
    func start() throws
    func stop()
    func pause()
    func resume()

    var onFrame: ((AudioFrame) -> Void)? { get set }
    var onAudioFocusChanged: ((Bool) -> Void)? { get set }
}
