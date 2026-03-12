import Foundation

final class SessionEventEmitter {
    private weak var delegate: EkaScribeDelegate?
    private let scribe: EkaScribe
    private let sessionId: String

    init(delegate: EkaScribeDelegate?, scribe: EkaScribe, sessionId: String) {
        self.delegate = delegate
        self.scribe = scribe
        self.sessionId = sessionId
    }

    func emit(_ eventName: SessionEventName, _ eventType: EventType, _ message: String, _ metadata: [String: String] = [:]) {
        let event = SessionEvent(
            sessionId: sessionId,
            eventName: eventName,
            eventType: eventType,
            message: message,
            metadata: metadata,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        delegate?.scribe(scribe, didEmitEvent: event)
    }
}
