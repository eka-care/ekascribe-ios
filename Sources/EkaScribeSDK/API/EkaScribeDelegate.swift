import Foundation

public protocol EkaScribeDelegate: AnyObject {
    func scribe(_ scribe: EkaScribe, didStartSession sessionId: String)
    func scribe(_ scribe: EkaScribe, didPauseSession sessionId: String)
    func scribe(_ scribe: EkaScribe, didResumeSession sessionId: String)
    func scribe(_ scribe: EkaScribe, didStopSession sessionId: String, chunkCount: Int)
    func scribe(_ scribe: EkaScribe, didFailWithError error: ScribeError)

    func scribe(_ scribe: EkaScribe, didCompleteSession sessionId: String, result: SessionResult)
    func scribe(_ scribe: EkaScribe, didFailSession sessionId: String, error: ScribeError)
    func scribe(_ scribe: EkaScribe, didChangeAudioFocus hasFocus: Bool)
    func scribe(_ scribe: EkaScribe, didEmitEvent event: SessionEvent)
    func scribe(_ scribe: EkaScribe, didCancelSession sessionId: String)
}

public extension EkaScribeDelegate {
    func scribe(_ scribe: EkaScribe, didCompleteSession sessionId: String, result: SessionResult) {}
    func scribe(_ scribe: EkaScribe, didFailSession sessionId: String, error: ScribeError) {}
    func scribe(_ scribe: EkaScribe, didChangeAudioFocus hasFocus: Bool) {}
    func scribe(_ scribe: EkaScribe, didEmitEvent event: SessionEvent) {}
    func scribe(_ scribe: EkaScribe, didCancelSession sessionId: String) {}
}
