import Foundation

public struct SessionEvent: Sendable {
    public let sessionId: String
    public let eventName: SessionEventName
    public let eventType: EventType
    public let message: String
    public var metadata: [String: String]
    public let timestampMs: Int

    public init(
        sessionId: String,
        eventName: SessionEventName,
        eventType: EventType,
        message: String,
        metadata: [String: String] = [:],
        timestampMs: Int
    ) {
        self.sessionId = sessionId
        self.eventName = eventName
        self.eventType = eventType
        self.message = message
        self.metadata = metadata
        self.timestampMs = timestampMs
    }
}

public enum EventType: String, Sendable {
    case success
    case error
    case info
}

public enum SessionEventName: String, Sendable {
    case sessionStartInitiated
    case recordingStarted
    case sessionStartFailed
    case sessionPaused
    case sessionResumed
    case sessionStopInitiated
    case sessionCompleted
    case sessionFailed
    case audioFocusChanged
    case modelDownloadStarted
    case modelDownloadCompleted
    case modelDownloadFailed
    case modelDownloadCached
    case pipelineStopped
    case chunkUploaded
    case chunkUploadFailed
    case chunkProcessingFailed
    case uploadRetryStarted
    case uploadRetryCompleted
    case initTransactionSuccess
    case initTransactionFailed
    case stopTransactionSuccess
    case stopTransactionFailed
    case commitTransactionSuccess
    case commitTransactionFailed
    case pollResultFailed
    case pollResultTimeout
    case fullAudioGenerated
    case fullAudioGenerationFailed
    case fullAudioUploaded
    case fullAudioUploadFailed
}
