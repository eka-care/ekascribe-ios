# EkaScribeSDK — Public API Reference

This document is the authoritative reference for every public type, method, and property exposed by EkaScribeSDK. Types are grouped by concern. All types conform to `Sendable` unless noted otherwise.

---

## Table of Contents

1. [EkaScribe](#ekascribe) — Singleton entry point
2. [EkaScribeConfig](#ekascribeconfig) — SDK configuration
3. [EkaScribeEnvironment](#ekascribeenvironment) — Backend environment
4. [ScribeClientInfo](#scribeclientinfo) — Client identification
5. [EkaScribeDelegate](#ekascribedelegate) — Lifecycle callbacks
6. [EkaScribeTokenStorage](#ekascribetokenstorage) — Token management protocol
7. [SessionConfig](#sessionconfig) — Session parameters
8. [OutputTemplate](#outputtemplate) — Template selection
9. [PatientDetail](#patientdetail) — Optional patient metadata
10. [SessionState](#sessionstate) — Session state machine
11. [SessionResult](#sessionresult) — Transcription output container
12. [TemplateOutput](#templateoutput) — Per-template output
13. [SectionData](#sectiondata) — Individual output section
14. [TemplateType](#templatetype) — Output format kind
15. [SessionEvent](#sessionevent) — Granular observability events
16. [SessionEventName](#sessioneventname) — Event name enum
17. [EventType](#eventtype) — Event severity
18. [ScribeError](#scribeerror) — Error container
19. [ErrorCode](#errorcode) — All error codes
20. [TransactionResult](#transactionresult) — Retry outcome
21. [VoiceActivityData](#voiceactivitydata) — Real-time speech detection
22. [AudioQualityMetrics](#audioqualitymetrics) — Audio quality scores
23. [AnalyserState](#analyserstate) — SQUIM model state
24. [UploadStage](#uploadstage) — Session upload lifecycle
25. [SampleRate](#samplerate) — Audio sample rate options
26. [FrameSize](#framesize) — Audio frame size options
27. [ScribeSession](#scribesession) — Persisted session record
28. [ScribeHistoryItem](#scribehistoryitem) — Backend history entry
29. [ScribePatientInfo](#scribepatientinfo) — Patient info from history
30. [TemplateItem](#templateitem) — Template catalogue entry
31. [SessionData](#sessiondata) — Edited session payload
32. [UserConfigs](#userconfigs) — User preference configuration
33. [ConsultationMode](#consultationmode) — Mode descriptor
34. [SupportedLanguage](#supportedlanguage) — Language descriptor
35. [ConfigOutputTemplate](#configoutputtemplate) — Template descriptor from config
36. [ModelType](#modeltype) — Model descriptor
37. [SelectedUserPreferences](#selecteduserpreferences) — Saved user preferences

---

## EkaScribe

```swift
public final class EkaScribe: @unchecked Sendable
```

The SDK singleton. All functionality is accessed through `EkaScribe.shared`. Must be initialized with `initialize(config:delegate:)` before any other method is called.

### Properties

| Property | Type | Description |
|---|---|---|
| `shared` | `EkaScribe` | The singleton instance. |
| `analyserState` | `AnalyserState` | `@Published` — current state of the SQUIM ONNX model downloader. Observe with Combine. |

### Methods

#### `initialize(config:delegate:)`

```swift
public func initialize(config: EkaScribeConfig, delegate: EkaScribeDelegate) throws
```

Wires up all internal components (database, network client, pipeline factory, session manager). Must be called once before any other SDK method. Throws if the SQLite database cannot be opened.

---

#### `startSession(config:onStart:onError:)`

```swift
public func startSession(
    config: SessionConfig,
    onStart: @escaping (String) -> Void = { _ in },
    onError: @escaping (ScribeError) -> Void = { _ in }
) async throws
```

Starts a new recording session. Requests microphone permission if needed. Throws `ScribeError` if the SDK is not initialized or a session is already active.

| Parameter | Type | Description |
|---|---|---|
| `config` | `SessionConfig` | Session parameters (languages, mode, templates, etc.). |
| `onStart` | `(String) -> Void` | Called with the session ID once the audio engine is running. |
| `onError` | `(ScribeError) -> Void` | Called if startup fails before the first delegate callback. |

---

#### `pauseSession()`

```swift
public func pauseSession()
```

Pauses audio capture. Buffered frames are retained. Safe to call during `.recording` state only.

---

#### `resumeSession()`

```swift
public func resumeSession()
```

Resumes audio capture after a pause.

---

#### `stopSession()`

```swift
public func stopSession()
```

Stops audio capture, drains the pipeline, and triggers the backend stop → commit sequence. Results arrive via `didCompleteSession`.

---

#### `cancelSession()`

```swift
public func cancelSession()
```

Aborts the current session without committing it to the backend. No transcription result is produced.

---

#### `isRecording()`

```swift
public func isRecording() -> Bool
```

Returns `true` when the session state is `.recording`.

---

#### `getSessionState()`

```swift
public func getSessionState() throws -> AnyPublisher<SessionState, Never>
```

Returns a Combine publisher that emits every `SessionState` transition. Replays the current state to new subscribers (`CurrentValueSubject`). Throws if not initialized.

---

#### `getVoiceActivity()`

```swift
public func getVoiceActivity() throws -> AnyPublisher<VoiceActivityData, Never>
```

Returns a publisher that emits one `VoiceActivityData` per audio frame (~20 ms). Use for waveform / speech indicator UI. Throws if not initialized.

---

#### `getAudioQuality()`

```swift
public func getAudioQuality() throws -> AnyPublisher<AudioQualityMetrics, Never>
```

Returns a publisher that emits `AudioQualityMetrics` every 3 seconds (when the SQUIM analyser is available). Throws if not initialized.

---

#### `getUploadProgress(sessionId:)`

```swift
public func getUploadProgress(sessionId: String) throws -> AnyPublisher<UploadStage?, Never>
```

Observes the `UploadStage` of a specific session from the local database. Emits `nil` when the session is not found. Throws if not initialized.

---

#### `getSessions()`

```swift
public func getSessions() async throws -> [ScribeSession]
```

Returns all sessions persisted in the local SQLite database.

---

#### `getSession(_:)`

```swift
public func getSession(_ sessionId: String) async throws -> ScribeSession?
```

Returns the persisted record for a single session, or `nil` if not found.

---

#### `retrySession(_:forceCommit:)`

```swift
public func retrySession(_ sessionId: String, forceCommit: Bool = false) async throws -> TransactionResult
```

Resumes an incomplete session from the last successful upload stage (idempotent). Pass `forceCommit: true` to skip the stop step and commit directly.

---

#### `getSessionOutput(_:)`

```swift
public func getSessionOutput(_ sessionId: String) async -> Result<SessionResult, Error>
```

Makes a single attempt to fetch the transcription result for the given session from the backend. Returns `.failure` if the result is not yet ready.

---

#### `pollSessionResult(_:)`

```swift
public func pollSessionResult(_ sessionId: String) async -> Result<SessionResult, Error>
```

Polls `getSessionOutput` up to `pollMaxRetries` times (default 3), waiting `pollDelayMs` ms (default 2000 ms) between attempts. Returns `.failure(.pollTimeout)` if no result arrives in time.

---

#### `convertTransactionResult(_:templateId:)`

```swift
public func convertTransactionResult(_ sessionId: String, templateId: String) async -> Result<Bool, Error>
```

Requests the backend to convert the session output to a different template format.

---

#### `updateSessionResult(_:updatedData:)`

```swift
public func updateSessionResult(_ sessionId: String, updatedData: [SessionData]) async -> Result<Bool, Error>
```

Pushes edited template data back to the backend.

---

#### `getTemplates()`

```swift
public func getTemplates() async -> Result<[TemplateItem], Error>
```

Fetches the full template catalogue from the backend.

---

#### `updateTemplates(favouriteTemplates:)`

```swift
public func updateTemplates(favouriteTemplates: [String]) async -> Result<Void, Error>
```

Saves the user's favourite template IDs to the backend.

---

#### `getUserConfigs()`

```swift
public func getUserConfigs() async -> Result<UserConfigs, Error>
```

Fetches user preferences (consultation modes, supported languages, output templates, model configs) from the backend.

---

#### `updateUserConfigs(_:)`

```swift
public func updateUserConfigs(_ prefs: SelectedUserPreferences) async -> Result<Bool, Error>
```

Saves updated user preferences to the backend.

---

#### `getHistory(count:)`

```swift
public func getHistory(count: Int? = nil) async throws -> [ScribeHistoryItem]
```

Returns past session entries from the backend. Pass `count` to limit results; `nil` returns all available items.

---

#### `getFullAudioFile()`

```swift
public func getFullAudioFile() -> URL?
```

Returns the local file URL of the concatenated full audio file from the most recent session, or `nil` if `fullAudioOutput` was disabled or the file does not exist.

---

#### `destroy()`

```swift
public func destroy()
```

Tears down all internal components and resets the singleton to an uninitialized state. Call on app logout or when the SDK is no longer needed.

---

## EkaScribeConfig

```swift
public struct EkaScribeConfig
```

Value type carrying all SDK configuration. Pass to `EkaScribe.shared.initialize()`.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `environment` | `EkaScribeEnvironment` | `.production` | Backend environment to target. |
| `clientInfo` | `ScribeClientInfo` | *(required)* | Client ID and flavour string sent with every request. |
| `tokenStorage` | `any EkaScribeTokenStorage` | *(required)* | Protocol implementation for access/refresh token management. |
| `sampleRate` | `SampleRate` | `.hz16000` | PCM sample rate used for recording and VAD. |
| `frameSize` | `FrameSize` | `.samples512` | Number of samples per audio frame. |
| `enableAnalyser` | `Bool` | `true` | When `true`, downloads and runs the SQUIM ONNX quality model. |
| `debugMode` | `Bool` | `false` | When `true`, enables verbose stdout logging via `DefaultLogger`. |
| `fullAudioOutput` | `Bool` | `false` | When `true`, concatenates all chunk PCM into a single full audio file. |

### Internal-only constants (not configurable via init)

| Constant | Value | Description |
|---|---|---|
| `preferredChunkDurationSec` | `10` | Target chunk duration (s) for the preferred VAD cut. |
| `desperationChunkDurationSec` | `20` | Minimum duration (s) before the desperation cut. |
| `maxChunkDurationSec` | `25` | Hard maximum chunk duration (s); forces a cut regardless of VAD. |
| `overlapDurationSec` | `0.5` | Overlap duration (s) between consecutive chunks. |
| `maxUploadRetries` | `2` | Maximum S3 upload retry attempts per chunk. |
| `pollMaxRetries` | `3` | Maximum polling attempts when fetching transcription results. |
| `pollDelayMs` | `2000` | Delay in milliseconds between polling attempts. |

---

## EkaScribeEnvironment

```swift
public enum EkaScribeEnvironment: Sendable
```

Selects the backend tier and S3 bucket for the SDK.

| Case | Base URL | Credentials URL | S3 Bucket |
|---|---|---|---|
| `.production` | `https://api.eka.care` | `https://cog.eka.care/credentials` | `m-prod-voice-record` |
| `.staging` | `https://api.staging.eka.care` | `https://cog.staging.eka.care/credentials` | `m-staging-voice-record` |
| `.dev` | `https://api.dev.eka.care` | `https://cog.dev.eka.care/credentials` | `m-dev-voice-record` |

All environments use the same refresh-token path: `/connect-auth/v1/account/refresh-token`.

---

## ScribeClientInfo

```swift
public struct ScribeClientInfo: Sendable
```

Identifies the integrating app on every API request.

| Property | Type | Default | Description |
|---|---|---|---|
| `clientId` | `String` | *(required)* | Unique client identifier issued by Eka. Sent as the `client-id` header. |
| `flavour` | `String` | `"ScribeIOS"` | Application flavour string included in request metadata. |

---

## EkaScribeDelegate

```swift
public protocol EkaScribeDelegate: AnyObject
```

Receives lifecycle events from the SDK. Adopt this protocol and pass the conforming object to `initialize(config:delegate:)`.

### Required Methods

| Method | Description |
|---|---|
| `scribe(_:didStartSession:)` | The session has started and audio capture is active. `sessionId` is the UUID for this session. |
| `scribe(_:didPauseSession:)` | Audio capture has been paused. |
| `scribe(_:didResumeSession:)` | Audio capture has resumed after a pause. |
| `scribe(_:didStopSession:chunkCount:)` | Audio capture has stopped. `chunkCount` is the total chunks recorded. |
| `scribe(_:didFailWithError:)` | A non-session error occurred (e.g. initialization issue). |

### Optional Methods (default empty implementations provided)

| Method | Description |
|---|---|
| `scribe(_:didCompleteSession:result:)` | Full output is ready. `result` contains all requested templates. |
| `scribe(_:didReadyTranscript:result:)` | Phase 1 transcript is ready (faster). App may start a new session immediately after this. |
| `scribe(_:didReadyOutput:result:)` | Phase 2 full template output is ready. |
| `scribe(_:didFailSession:error:)` | The session ended with an unrecoverable error. |
| `scribe(_:didChangeAudioFocus:hasFocus:)` | Audio route changed. `hasFocus: false` means another app interrupted recording. |
| `scribe(_:didEmitEvent:)` | A granular `SessionEvent` was emitted for observability / debugging. |
| `scribe(_:didCancelSession:)` | The session was cancelled without producing a result. |

---

## EkaScribeTokenStorage

```swift
public protocol EkaScribeTokenStorage: AnyObject, Sendable
```

Provides token management. Implement and pass to `EkaScribeConfig`.

| Method | Signature | Description |
|---|---|---|
| `getAccessToken()` | `() -> String?` | Returns the current access (bearer) token, or `nil` if not available. |
| `getRefreshToken()` | `() -> String?` | Returns the current refresh token, or `nil` if not available. |
| `saveTokens(accessToken:refreshToken:)` | `(String, String) -> Void` | Called after a successful token refresh. Persist both tokens. |
| `onSessionExpired()` | `() -> Void` | Called when the refresh token itself is rejected. Redirect user to login. |

---

## SessionConfig

```swift
public struct SessionConfig: Sendable
```

Parameters for a single recording session. Pass to `startSession(config:)`.

| Property | Type | Default | Description |
|---|---|---|---|
| `languages` | `[String]` | *(required)* | BCP-47 language codes for transcription (e.g. `["en"]`, `["hi", "en"]`). |
| `mode` | `String` | *(required)* | Consultation mode ID (e.g. `"consultation"`). Use `ConsultationMode.id` from `getUserConfigs()`. |
| `modelType` | `String` | *(required)* | Model type ID (e.g. `"pro"`). Use `ModelType.id` from `getUserConfigs()`. |
| `outputTemplates` | `[OutputTemplate]?` | `nil` | Templates to generate. `nil` uses the backend default. |
| `patientDetails` | `PatientDetail?` | `nil` | Optional patient context included in the transcription request. |
| `section` | `String?` | `nil` | Optional section hint for the transcription. |
| `speciality` | `String?` | `nil` | Medical speciality hint (e.g. `"cardiology"`). |

---

## OutputTemplate

```swift
public struct OutputTemplate: Sendable, Codable
```

Selects a specific output template for a session.

| Property | Type | Default | Description |
|---|---|---|---|
| `templateId` | `String` | *(required)* | Template identifier. Use `TemplateItem.id` from `getTemplates()`. |
| `templateType` | `String` | `"custom"` | Template type hint sent to the backend. |
| `templateName` | `String?` | `nil` | Optional human-readable name. |

---

## PatientDetail

```swift
public struct PatientDetail: Sendable
```

Optional patient context to attach to a session. All fields are optional.

| Property | Type | Description |
|---|---|---|
| `age` | `Int?` | Patient age in years. |
| `biologicalSex` | `String?` | Biological sex string (e.g. `"M"`, `"F"`). |
| `name` | `String?` | Patient display name. |
| `patientId` | `String?` | External patient identifier from the host app. |
| `visitId` | `String?` | External visit/encounter identifier. |

---

## SessionState

```swift
public enum SessionState: String, Codable, Sendable
```

The current state of the session lifecycle. Published via `getSessionState()`.

| Case | Description |
|---|---|
| `.idle` | No active session. Initial state after init or after a completed/error session resets. |
| `.starting` | `startSession()` called; microphone permission being requested and audio engine starting. |
| `.recording` | Audio is actively being captured and streamed through the pipeline. |
| `.paused` | Audio capture is paused. Frames are buffered. |
| `.stopping` | `stopSession()` called; pipeline draining and backend stop/commit underway. |
| `.processing` | Pipeline drained; waiting for the backend to complete transcription. |
| `.completed` | Session finished successfully. Results delivered via delegate. |
| `.error` | An unrecoverable error occurred. Session resets to `.idle` after delivery. |

#### `canTransition(to:)`

```swift
public func canTransition(to target: SessionState) -> Bool
```

Returns `true` if the transition from the current state to `target` is valid. Invalid transitions log a warning and move the session to `.error`.

---

## SessionResult

```swift
public struct SessionResult: Sendable
```

The top-level result of a completed session.

| Property | Type | Description |
|---|---|---|
| `templates` | `[TemplateOutput]` | One entry per requested output template (SOAP, transcript, custom, etc.). |
| `audioQuality` | `Double?` | Overall audio quality score (0.0–1.0), if the SQUIM analyser ran. |

---

## TemplateOutput

```swift
public struct TemplateOutput: Sendable
```

Output for a single requested template.

| Property | Type | Description |
|---|---|---|
| `name` | `String?` | Internal template name. |
| `title` | `String?` | Display title for the template (e.g. `"SOAP Note"`). |
| `sections` | `[SectionData]` | Ordered list of labelled sections in this template. |
| `sessionId` | `String` | The session ID this output belongs to. |
| `templateId` | `String?` | Template identifier. |
| `documentId` | `String?` | Backend document ID. Required for `updateSessionResult()`. |
| `isEditable` | `Bool` | Whether this template output can be edited and pushed back. |
| `type` | `TemplateType` | Output format (`.markdown`, `.json`, `.ekaEmr`). |
| `rawOutput` | `String?` | Raw string payload from the backend, before section parsing. |

---

## SectionData

```swift
public struct SectionData: Sendable
```

A single labelled section within a `TemplateOutput`.

| Property | Type | Description |
|---|---|---|
| `title` | `String?` | Section heading (e.g. `"Subjective"`, `"Assessment"`). |
| `value` | `String?` | Section body text or JSON string. |

---

## TemplateType

```swift
public enum TemplateType: String, Codable, Sendable
```

Describes the format of a `TemplateOutput`.

| Case | Raw Value | Description |
|---|---|---|
| `.markdown` | `"markdown"` | Sections contain Markdown-formatted text. |
| `.json` | `"json"` | Sections contain JSON strings. |
| `.ekaEmr` | `"eka_emr"` | Eka EMR-specific structured format. |

---

## SessionEvent

```swift
public struct SessionEvent: Sendable
```

Granular observability event emitted throughout a session's lifecycle. Delivered via `scribe(_:didEmitEvent:)`.

| Property | Type | Description |
|---|---|---|
| `sessionId` | `String` | Session this event belongs to. |
| `eventName` | `SessionEventName` | Specific event identifier. |
| `eventType` | `EventType` | Severity: `.success`, `.info`, or `.error`. |
| `message` | `String` | Human-readable event description. |
| `metadata` | `[String: String]` | Optional key-value pairs with extra context. |
| `timestampMs` | `Int` | Client-side Unix epoch milliseconds. |

---

## SessionEventName

```swift
public enum SessionEventName: String, Sendable
```

All possible event names. Useful for logging, analytics, and debugging.

| Case | Description |
|---|---|
| `sessionStartInitiated` | `startSession()` was called. |
| `recordingStarted` | AVAudioEngine is running. |
| `sessionStartFailed` | Failed to start the audio engine or handshake. |
| `sessionPaused` | Session paused. |
| `sessionResumed` | Session resumed. |
| `sessionStopInitiated` | `stopSession()` was called. |
| `sessionCompleted` | Session completed successfully. |
| `sessionFailed` | Session ended with an error. |
| `audioFocusChanged` | Audio route changed (e.g. headphone plug/unplug, interruption). |
| `modelDownloadStarted` | SQUIM ONNX model download started. |
| `modelDownloadCompleted` | SQUIM model download finished. |
| `modelDownloadFailed` | SQUIM model download failed. |
| `modelDownloadCached` | SQUIM model was already cached (ETag hit). |
| `pipelineStopped` | Pipeline drain complete. |
| `chunkEncoded` | An audio chunk was encoded to M4A. |
| `chunkUploadStarted` | S3 upload started for a chunk. |
| `chunkUploaded` | S3 upload succeeded for a chunk. |
| `chunkUploadFailed` | S3 upload failed for a chunk. |
| `chunkProcessingFailed` | Chunk encoding or persistence failed. |
| `chunkRetryStarted` | Retry started for a failed chunk upload. |
| `chunkRetrySuccess` | Chunk upload succeeded on retry. |
| `chunkRetryFailed` | Chunk upload retry failed. |
| `uploadRetryStarted` | Session-level upload retry started. |
| `uploadRetryCompleted` | Session-level upload retry completed. |
| `initTransactionSuccess` | Init API call succeeded. |
| `initTransactionFailed` | Init API call failed. |
| `stopTransactionSuccess` | Stop API call succeeded. |
| `stopTransactionFailed` | Stop API call failed. |
| `commitTransactionSuccess` | Commit API call succeeded. |
| `commitTransactionFailed` | Commit API call failed. |
| `pollResultSuccess` | Result poll returned a transcript. |
| `pollResultFailed` | Result poll returned an error. |
| `pollResultTimeout` | Result poll timed out. |
| `transcriptReady` | Phase 1 transcript is available. |
| `outputReady` | Phase 2 full output is available. |
| `sessionResultReceived` | Combined result delivered to the delegate. |
| `recorderSetupFailed` | AVAudioEngine setup failed. |
| `fullAudioGenerated` | Full audio concatenation completed. |
| `fullAudioGenerationFailed` | Full audio concatenation failed. |
| `fullAudioUploaded` | Full audio file uploaded to S3. |
| `fullAudioUploadFailed` | Full audio S3 upload failed. |
| `sessionCancelled` | Session was cancelled. |
| `micSelected` | Microphone input route selected. |
| `micRouteChanged` | Microphone route changed during recording. |

---

## EventType

```swift
public enum EventType: String, Sendable
```

| Case | Description |
|---|---|
| `.success` | Operation completed successfully. |
| `.error` | An error occurred. |
| `.info` | Informational lifecycle event. |

---

## ScribeError

```swift
public struct ScribeError: Error, Sendable
```

The error type passed to delegate error callbacks and thrown methods.

| Property | Type | Description |
|---|---|---|
| `code` | `ErrorCode` | Machine-readable error category. |
| `message` | `String` | Human-readable error description. |
| `isRecoverable` | `Bool` | `true` if the app can retry (e.g. via `retrySession()`). Default `false`. |

---

## ErrorCode

```swift
public enum ErrorCode: String, Codable, Sendable
```

| Case | Description |
|---|---|
| `micPermissionDenied` | The user denied microphone permission. |
| `sessionAlreadyActive` | `startSession()` called while a session is already running. |
| `invalidConfig` | `initialize()` was not called before using the SDK, or config is invalid. |
| `encoderFailed` | PCM → M4A encoding failed for a chunk. |
| `uploadFailed` | S3 upload failed after all retries. |
| `modelLoadFailed` | SQUIM ONNX model could not be loaded or is corrupted. |
| `networkUnavailable` | No network connectivity detected. |
| `dbError` | SQLite database read/write error. |
| `invalidStateTransition` | An illegal session state transition was attempted. |
| `initTransactionFailed` | The backend `/init` API call failed. |
| `stopTransactionFailed` | The backend `/stop` API call failed. |
| `commitTransactionFailed` | The backend `/commit` API call failed. |
| `pollTimeout` | Transcription result polling timed out after `pollMaxRetries` attempts. |
| `transcriptionFailed` | The backend returned an error during transcription. |
| `recorderSetupFailed` | AVAudioEngine could not be configured or started. |
| `retryExhausted` | All automatic retry attempts have been exhausted. |
| `txnLimitReached` | The backend transaction limit for this client has been reached. |
| `unknown` | An unclassified error. Inspect `message` for details. |

---

## TransactionResult

```swift
public enum TransactionResult
```

Return value of `retrySession(_:forceCommit:)`.

| Case | Associated Values | Description |
|---|---|---|
| `.success` | `folderName: String`, `bid: String` | The transaction progressed successfully. `bid` is the backend transaction ID. |
| `.error` | `message: String`, `code: ErrorCode?` | The transaction failed. |

---

## VoiceActivityData

```swift
public struct VoiceActivityData: Sendable
```

Real-time per-frame speech detection result. Published via `getVoiceActivity()` approximately every 20 ms.

| Property | Type | Description |
|---|---|---|
| `isSpeech` | `Bool` | `true` if libfvad classified this frame as speech. |
| `amplitude` | `Float` | Normalised amplitude of the frame (0.0–1.0). Use for waveform rendering. |
| `timestampMs` | `Int` | Client-side Unix epoch milliseconds for this frame. |

---

## AudioQualityMetrics

```swift
public struct AudioQualityMetrics: Sendable
```

SQUIM ONNX model output. Published via `getAudioQuality()` every ~3 seconds when the analyser is available.

| Property | Type | Description |
|---|---|---|
| `stoi` | `Float` | Short-Time Objective Intelligibility score (0.0–1.0; higher is better). |
| `pesq` | `Float` | Perceptual Evaluation of Speech Quality score (range ~-0.5 to 4.5; higher is better). |
| `siSDR` | `Float` | Scale-Invariant Signal-to-Distortion Ratio in dB (higher is better). |
| `overallScore` | `Float` | Composite score derived from the above three metrics. Persisted in `AudioChunkRecord`. |

---

## AnalyserState

```swift
public enum AnalyserState: Sendable
```

Published on `EkaScribe.shared.$analyserState`. Tracks the SQUIM ONNX model download lifecycle.

| Case | Associated Values | Description |
|---|---|---|
| `.disabled` | — | `enableAnalyser` is `false`. No model will be downloaded. |
| `.idle` | — | Analyser is enabled but the download has not started. |
| `.downloading` | `progressPercent: Int` | Model download is in progress. `progressPercent` is 0–100. |
| `.ready` | `modelPath: String` | Model is downloaded and loaded. `modelPath` is the local file path. |
| `.failed` | `error: String` | Download or load failed. |

---

## UploadStage

```swift
public enum UploadStage: String, Codable, Sendable
```

Represents the backend handshake stage of a session. Used in `ScribeSession.uploadStage` and the `getUploadProgress()` publisher.

| Case | Raw Value | Description |
|---|---|---|
| `.initialize` | `"INIT"` | Init API call sent to the backend. |
| `.stop` | `"STOP"` | Stop API call sent. |
| `.commit` | `"COMMIT"` | Commit API call sent; backend is processing. |
| `.analyzing` | `"ANALYZING"` | Backend is transcribing. |
| `.completed` | `"COMPLETED"` | Transcription complete. |
| `.failure` | `"FAILURE"` | Session ended with a backend failure. |
| `.error` | `"ERROR"` | Session ended with an SDK-level error. |
| `.cancelled` | `"CANCELLED"` | Session was cancelled. |

---

## SampleRate

```swift
public enum SampleRate: Sendable
```

Audio sample rate for recording. Configured via `EkaScribeConfig.sampleRate`.

| Case | `intValue` | Notes |
|---|---|---|
| `.hz8000` | `8000` | Telephony quality. |
| `.hz16000` | `16000` | **Default.** Recommended for VAD and speech recognition. |
| `.hz32000` | `32000` | Wideband audio. |
| `.hz48000` | `48000` | Studio quality. |

---

## FrameSize

```swift
public enum FrameSize: Sendable
```

Number of PCM samples per audio frame. Configured via `EkaScribeConfig.frameSize`.

| Case | `intValue` | Notes |
|---|---|---|
| `.samples160` | `160` | 10 ms at 16 kHz. |
| `.samples320` | `320` | 20 ms at 16 kHz. Matches libfvad native sub-frame. |
| `.samples480` | `480` | 30 ms at 16 kHz. |
| `.samples512` | `512` | **Default.** ~32 ms at 16 kHz. |

---

## ScribeSession

```swift
public struct ScribeSession: Sendable
```

A lightweight session record returned from `getSessions()` / `getSession(_:)`. Read from local SQLite.

| Property | Type | Description |
|---|---|---|
| `sessionId` | `String` | UUID for this session. |
| `createdAt` | `Int` | Unix epoch milliseconds when the session was created. |
| `updatedAt` | `Int` | Unix epoch milliseconds of the last state change. |
| `state` | `String` | Raw `SessionState` value (e.g. `"completed"`). |
| `chunkCount` | `Int` | Number of audio chunks recorded in this session. |
| `uploadStage` | `UploadStage` | Last known upload lifecycle stage. |

---

## ScribeHistoryItem

```swift
public struct ScribeHistoryItem: Sendable
```

A past session entry fetched from the backend via `getHistory(count:)`. All properties are optional (backend may omit fields).

| Property | Type | Description |
|---|---|---|
| `bId` | `String?` | Backend ID. |
| `createdAt` | `String?` | ISO-8601 timestamp of session creation. |
| `flavour` | `String?` | Application flavour string. |
| `mode` | `String?` | Consultation mode used. |
| `oid` | `String?` | Organisation/owner ID. |
| `processingStatus` | `String?` | Backend processing status string. |
| `txnId` | `String?` | Backend transaction ID. |
| `userStatus` | `String?` | User-facing status string. |
| `uuid` | `String?` | Session UUID. |
| `version` | `String?` | API version string. |
| `patientDetails` | `ScribePatientInfo?` | Patient info associated with this session. |

---

## ScribePatientInfo

```swift
public struct ScribePatientInfo: Sendable
```

Patient information returned in `ScribeHistoryItem`.

| Property | Type | Description |
|---|---|---|
| `age` | `Int?` | Patient age in years. |
| `biologicalSex` | `String?` | Biological sex string. |
| `name` | `String?` | Patient name. |
| `patientId` | `String?` | External patient identifier. |
| `visitId` | `String?` | External visit identifier. |

---

## TemplateItem

```swift
public struct TemplateItem: Sendable
```

A template catalogue entry returned from `getTemplates()`.

| Property | Type | Description |
|---|---|---|
| `id` | `String` | Unique template identifier. Pass this as `OutputTemplate.templateId`. |
| `title` | `String` | Display name of the template. |
| `desc` | `String?` | Description of the template's purpose. |
| `isDefault` | `Bool` | Whether this is a system default template. |
| `isFavorite` | `Bool` | Whether the user has marked this template as a favourite. |
| `sectionIds` | `[String]` | IDs of sections included in this template. |

---

## SessionData

```swift
public struct SessionData: Sendable
```

Edited template output to push back to the backend via `updateSessionResult(_:updatedData:)`.

| Property | Type | Description |
|---|---|---|
| `templateId` | `String` | Template ID of the output being edited. |
| `documentId` | `String` | Document ID from `TemplateOutput.documentId`. |
| `data` | `String` | Serialised updated content (Markdown, JSON, or EMR string). |

---

## UserConfigs

```swift
public struct UserConfigs: Sendable
```

Top-level container returned by `getUserConfigs()`.

| Property | Type | Description |
|---|---|---|
| `consultationModes` | `ConsultationModeConfig` | Available consultation modes and max selection count. |
| `supportedLanguages` | `SupportedLanguagesConfig` | Supported transcription languages and max selection. |
| `outputTemplates` | `OutputTemplatesConfig` | Available output templates (union of supported formats and user's saved templates). |
| `modelConfigs` | `ModelConfigs` | Available model types and max selection. |
| `selectedUserPreferences` | `SelectedUserPreferences` | The user's currently saved preferences. |

### Supporting Config Types

#### `ConsultationModeConfig`

| Property | Type | Description |
|---|---|---|
| `modes` | `[ConsultationMode]` | List of available consultation modes. |
| `maxSelection` | `Int` | Maximum number of modes the user can select. |

#### `SupportedLanguagesConfig`

| Property | Type | Description |
|---|---|---|
| `languages` | `[SupportedLanguage]` | List of supported transcription languages. |
| `maxSelection` | `Int` | Maximum number of languages selectable per session. |

#### `OutputTemplatesConfig`

| Property | Type | Description |
|---|---|---|
| `templates` | `[ConfigOutputTemplate]` | Deduplicated list of available output templates. |
| `maxSelection` | `Int` | Maximum number of templates selectable per session. |

#### `ModelConfigs`

| Property | Type | Description |
|---|---|---|
| `modelTypes` | `[ModelType]` | Available model types. |
| `maxSelection` | `Int` | Maximum number of model types selectable. |

---

## ConsultationMode

```swift
public struct ConsultationMode: Sendable
```

Describes a consultation mode option.

| Property | Type | Description |
|---|---|---|
| `id` | `String` | Identifier passed as `SessionConfig.mode`. |
| `name` | `String` | Display name (e.g. `"Consultation"`). |
| `desc` | `String` | Description of the mode. |

---

## SupportedLanguage

```swift
public struct SupportedLanguage: Sendable
```

Describes a supported transcription language.

| Property | Type | Description |
|---|---|---|
| `id` | `String` | BCP-47 language code (e.g. `"en"`, `"hi"`). Pass in `SessionConfig.languages`. |
| `name` | `String` | Display name (e.g. `"English"`). |

---

## ConfigOutputTemplate

```swift
public struct ConfigOutputTemplate: Sendable
```

A template descriptor returned as part of `UserConfigs`.

| Property | Type | Description |
|---|---|---|
| `id` | `String` | Template identifier. Pass as `OutputTemplate.templateId`. |
| `name` | `String` | Display name of the template. |

---

## ModelType

```swift
public struct ModelType: Sendable
```

Describes a transcription model option returned in `UserConfigs.modelConfigs`. **This is a struct, not an enum** — model types are dynamic and server-defined.

| Property | Type | Description |
|---|---|---|
| `id` | `String` | Model identifier. Pass as `SessionConfig.modelType`. |
| `name` | `String` | Display name (e.g. `"Pro"`). |
| `desc` | `String` | Description of the model's capabilities. |

---

## SelectedUserPreferences

```swift
public struct SelectedUserPreferences: Sendable
```

Represents the user's currently saved preferences, returned in `UserConfigs.selectedUserPreferences`. Also the input type for `updateUserConfigs(_:)`.

| Property | Type | Default | Description |
|---|---|---|---|
| `consultationMode` | `ConsultationMode?` | `nil` | The user's preferred consultation mode. |
| `languages` | `[SupportedLanguage]` | `[]` | The user's preferred transcription languages. |
| `outputTemplates` | `[ConfigOutputTemplate]` | `[]` | The user's selected output templates. |
| `modelType` | `ModelType?` | `nil` | The user's preferred model type. |
