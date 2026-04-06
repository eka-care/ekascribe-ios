# EkaScribeSDK

[![Swift](https://img.shields.io/badge/Swift-5.10+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015%2B-blue.svg)](https://developer.apple.com)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager)
[![License](https://img.shields.io/badge/License-MIT-lightgray.svg)](LICENSE)

EkaScribe is a voice-powered medical transcription SDK for iOS that records audio, performs real-time chunked uploads, and generates structured clinical documents using AI. It provides a complete pipeline from microphone capture to transcription output.

## Key Features

1. Real-time audio recording with chunked uploads to S3
2. Multi-language transcription support (up to 2 languages per session)
3. Multiple output templates (SOAP notes, custom formats)
4. Real-time voice activity detection (VAD) and audio quality analysis
5. Session retry and idempotent error recovery
6. Combine publishers for reactive state observation
7. On-device audio quality assessment via ONNX Runtime

## Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 15.0+          |
| Swift    | 5.10+          |
| Xcode    | 15.0+          |

## Installation

### Swift Package Manager

#### Xcode

1. Open your project in Xcode
2. Go to **File > Add Package Dependencies...**
3. Enter the repository URL:
   ```
   https://github.com/eka-care/ekascribe-ios.git
   ```
4. Set the dependency rule to **Up to Next Major Version** starting from `0.1.0`
5. Select the `EkaScribeSDK` library and add it to your target

#### Package.swift

Add EkaScribeSDK as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/eka-care/ekascribe-ios.git", from: "0.1.0")
]
```

Then add it to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EkaScribeSDK", package: "ekascribe-ios")
    ]
)
```

## Permissions

Add the following key to your app's `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Required for medical transcription recording</string>
```

**Important:** Microphone permission must be granted before starting a session. The SDK will return a `micPermissionDenied` error if permission is not available.

---

## Core Components

### 1. TokenStorage

The `EkaScribeTokenStorage` protocol manages authentication tokens. You must provide an implementation that handles token persistence and refresh.

```swift
import EkaScribeSDK

class MyTokenStorage: EkaScribeTokenStorage {
    func getAccessToken() -> String? {
        // Return your stored access token
        return KeychainManager.shared.getAccessToken()
    }

    func getRefreshToken() -> String? {
        // Return your stored refresh token
        return KeychainManager.shared.getRefreshToken()
    }

    func saveTokens(accessToken: String, refreshToken: String) {
        // Persist the refreshed token pair
        KeychainManager.shared.save(accessToken: accessToken, refreshToken: refreshToken)
    }

    func onSessionExpired() {
        // Handle session expiration (e.g., navigate to login)
        NotificationCenter.default.post(name: .sessionExpired, object: nil)
    }
}
```

| Method | Description |
|--------|-------------|
| `getAccessToken() -> String?` | Return the current access token for API authentication |
| `getRefreshToken() -> String?` | Return the current refresh token for token renewal |
| `saveTokens(accessToken:refreshToken:)` | Persist a new token pair after a successful refresh |
| `onSessionExpired()` | Called when token refresh fails and the session is no longer valid |

### 2. Delegate

The `EkaScribeDelegate` protocol receives session lifecycle events. There are 5 **required** methods and 5 **optional** methods.

```swift
class MyScribeDelegate: EkaScribeDelegate {
    // MARK: - Required Methods

    func scribe(_ scribe: EkaScribe, didStartSession sessionId: String) {
        print("Session started: \(sessionId)")
    }

    func scribe(_ scribe: EkaScribe, didPauseSession sessionId: String) {
        print("Session paused")
    }

    func scribe(_ scribe: EkaScribe, didResumeSession sessionId: String) {
        print("Session resumed")
    }

    func scribe(_ scribe: EkaScribe, didStopSession sessionId: String, chunkCount: Int) {
        print("Session stopped with \(chunkCount) chunks")
    }

    func scribe(_ scribe: EkaScribe, didFailWithError error: ScribeError) {
        print("Error [\(error.code)]: \(error.message)")
    }

    // MARK: - Optional Methods

    func scribe(_ scribe: EkaScribe, didCompleteSession sessionId: String, result: SessionResult) {
        // Called when transcription is ready
        for template in result.templates {
            print("Template: \(template.title ?? "")")
            for section in template.sections {
                print("  \(section.title ?? ""): \(section.value ?? "")")
            }
        }
    }

    func scribe(_ scribe: EkaScribe, didFailSession sessionId: String, error: ScribeError) {
        // Called when server-side processing fails
        print("Session \(sessionId) failed: \(error.message)")
    }

    func scribe(_ scribe: EkaScribe, didChangeAudioFocus hasFocus: Bool) {
        // Called when another app takes/releases audio focus
        print("Audio focus: \(hasFocus)")
    }

    func scribe(_ scribe: EkaScribe, didEmitEvent event: SessionEvent) {
        // Fine-grained lifecycle events for logging/analytics
        print("[\(event.eventType)] \(event.eventName): \(event.message)")
    }

    func scribe(_ scribe: EkaScribe, didCancelSession sessionId: String) {
        print("Session cancelled: \(sessionId)")
    }
}
```

#### Required Methods

| Method | Description |
|--------|-------------|
| `didStartSession(sessionId:)` | Recording has started successfully |
| `didPauseSession(sessionId:)` | Recording has been paused |
| `didResumeSession(sessionId:)` | Recording has been resumed |
| `didStopSession(sessionId:chunkCount:)` | Recording stopped, processing begins |
| `didFailWithError(error:)` | An error occurred during the session |

#### Optional Methods

| Method | Description |
|--------|-------------|
| `didCompleteSession(sessionId:result:)` | Transcription result is ready |
| `didFailSession(sessionId:error:)` | Server-side processing failed |
| `didChangeAudioFocus(hasFocus:)` | Audio focus gained or lost |
| `didEmitEvent(event:)` | Fine-grained session event for logging |
| `didCancelSession(sessionId:)` | Session was cancelled |

### 3. EkaScribeConfig

SDK-level configuration passed to `initialize()`.

```swift
let config = EkaScribeConfig(
    environment: .production,
    clientInfo: ScribeClientInfo(clientId: "your-client-id"),
    tokenStorage: MyTokenStorage(),
    sampleRate: .hz16000,
    frameSize: .samples512,
    enableAnalyser: true,
    debugMode: false,
    fullAudioOutput: false
)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `environment` | `EkaScribeEnvironment` | `.production` | Backend environment |
| `clientInfo` | `ScribeClientInfo` | *required* | Client identification |
| `tokenStorage` | `EkaScribeTokenStorage` | *required* | Token management implementation |
| `sampleRate` | `SampleRate` | `.hz16000` | Audio sample rate |
| `frameSize` | `FrameSize` | `.samples512` | Audio frame size in samples |
| `enableAnalyser` | `Bool` | `true` | Enable on-device audio quality analysis |
| `debugMode` | `Bool` | `false` | Enable debug logging |
| `fullAudioOutput` | `Bool` | `false` | Save and upload the full audio file |

#### EkaScribeEnvironment

| Case | API Endpoint |
|------|-------------|
| `.production` | `api.eka.care` |
| `.staging` | `api.staging.eka.care` |
| `.dev` | `api.dev.eka.care` |

#### SampleRate

| Case | Value |
|------|-------|
| `.hz8000` | 8,000 Hz |
| `.hz16000` | 16,000 Hz |
| `.hz32000` | 32,000 Hz |
| `.hz48000` | 48,000 Hz |

#### FrameSize

| Case | Value |
|------|-------|
| `.samples160` | 160 samples |
| `.samples320` | 320 samples |
| `.samples480` | 480 samples |
| `.samples512` | 512 samples |

#### ScribeClientInfo

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `clientId` | `String` | *required* | Your application identifier |
| `flavour` | `String` | `"ScribeIOS"` | Client flavour identifier |

### 4. SessionConfig

Per-session configuration passed to `startSession()`.

```swift
let sessionConfig = SessionConfig(
    languages: ["en-IN"],
    mode: "consultation",
    modelType: "pro",
    outputTemplates: [
        OutputTemplate(
            templateId: "your-template-id",
            templateName: "SOAP Notes"
        )
    ],
    patientDetails: PatientDetail(
        age: 45,
        biologicalSex: "male",
        name: "John Doe"
    ),
    speciality: "general_medicine"
)
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `languages` | `[String]` | Yes | Language codes (up to 2 per session, e.g. `"en-IN"`) |
| `mode` | `String` | Yes | Execution mode (`"consultation"`, `"dictation"`) |
| `modelType` | `String` | Yes | Model selection (`"pro"` for accuracy, `"lite"` for speed) |
| `outputTemplates` | `[OutputTemplate]?` | No | Output format templates |
| `patientDetails` | `PatientDetail?` | No | Patient context for transcription |
| `section` | `String?` | No | Section identifier |
| `speciality` | `String?` | No | Medical speciality for better transcription |

#### OutputTemplate

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `templateId` | `String` | *required* | Template identifier |
| `templateType` | `String` | `"custom"` | Template type |
| `templateName` | `String?` | `nil` | Display name |

#### PatientDetail

All properties are optional and provide context for transcription.

| Property | Type | Description |
|----------|------|-------------|
| `age` | `Int?` | Patient age |
| `biologicalSex` | `String?` | Patient biological sex |
| `name` | `String?` | Patient name |
| `patientId` | `String?` | External patient identifier |
| `visitId` | `String?` | External visit identifier |

---

## SDK Initialization

Call `initialize()` once before using any other SDK methods (typically in `AppDelegate` or on your recording screen's `viewDidLoad`):

```swift
import EkaScribeSDK

let config = EkaScribeConfig(
    environment: .production,
    clientInfo: ScribeClientInfo(clientId: "your-client-id"),
    tokenStorage: MyTokenStorage()
)

do {
    try EkaScribe.shared.initialize(config: config, delegate: MyScribeDelegate())
} catch {
    print("SDK initialization failed: \(error)")
}
```

---

## Session Management

### Starting a Session

```swift
let sessionConfig = SessionConfig(
    languages: ["en-IN"],
    mode: "consultation",
    modelType: "pro"
)

try await EkaScribe.shared.startSession(
    config: sessionConfig,
    onStart: { sessionId in
        print("Recording started: \(sessionId)")
    },
    onError: { error in
        print("Failed to start: \(error.message)")
    }
)
```

### Recording Controls

```swift
// Pause current recording
EkaScribe.shared.pauseSession()

// Resume paused recording
EkaScribe.shared.resumeSession()

// Stop recording and begin processing
EkaScribe.shared.stopSession()

// Cancel session without processing
EkaScribe.shared.cancelSession()

// Check if currently recording
let isActive = EkaScribe.shared.isRecording()
```

---

## Session State Flow

```
IDLE → STARTING → RECORDING ↔ PAUSED → STOPPING → PROCESSING → COMPLETED
                                                                    ↓
                              (error can occur from any state) → ERROR
```

| State | Description |
|-------|-------------|
| `idle` | No active session |
| `starting` | Session initialization in progress |
| `recording` | Actively recording audio |
| `paused` | Recording paused, can resume |
| `stopping` | Recording stopped, finalizing chunks |
| `processing` | Server-side transcription in progress |
| `completed` | Transcription result available |
| `error` | An error occurred |

### Observing State Changes

```swift
import Combine

var cancellables = Set<AnyCancellable>()

try EkaScribe.shared.getSessionState()
    .receive(on: DispatchQueue.main)
    .sink { state in
        switch state {
        case .idle:        updateUI(status: "Ready")
        case .starting:    updateUI(status: "Starting...")
        case .recording:   updateUI(status: "Recording")
        case .paused:      updateUI(status: "Paused")
        case .stopping:    updateUI(status: "Stopping...")
        case .processing:  updateUI(status: "Processing...")
        case .completed:   updateUI(status: "Done")
        case .error:       updateUI(status: "Error")
        }
    }
    .store(in: &cancellables)
```

---

## Real-Time Observation

The SDK provides 4 Combine publishers for real-time data streams.

### Voice Activity Detection

Monitor speech detection and audio amplitude in real time:

```swift
try EkaScribe.shared.getVoiceActivity()
    .receive(on: DispatchQueue.main)
    .sink { data in
        let status = data.isSpeech ? "Speaking" : "Silent"
        print("\(status) | Amplitude: \(data.amplitude)")
    }
    .store(in: &cancellables)
```

**VoiceActivityData:**

| Property | Type | Description |
|----------|------|-------------|
| `isSpeech` | `Bool` | Whether speech is detected |
| `amplitude` | `Float` | Current audio amplitude level |
| `timestampMs` | `Int` | Timestamp in milliseconds |

### Audio Quality Metrics

Monitor on-device audio quality assessment (requires `enableAnalyser: true`):

```swift
try EkaScribe.shared.getAudioQuality()
    .receive(on: DispatchQueue.main)
    .sink { metrics in
        print("Overall: \(metrics.overallScore)")
        print("STOI: \(metrics.stoi), PESQ: \(metrics.pesq), SI-SDR: \(metrics.siSDR)")
    }
    .store(in: &cancellables)
```

**AudioQualityMetrics:**

| Property | Type | Description |
|----------|------|-------------|
| `stoi` | `Float` | Short-Time Objective Intelligibility score |
| `pesq` | `Float` | Perceptual Evaluation of Speech Quality score |
| `siSDR` | `Float` | Scale-Invariant Signal-to-Distortion Ratio |
| `overallScore` | `Float` | Combined quality score |

### Upload Progress

Track the upload and processing stage for a session:

```swift
try EkaScribe.shared.getUploadProgress(sessionId: sessionId)
    .receive(on: DispatchQueue.main)
    .sink { stage in
        if let stage = stage {
            print("Upload stage: \(stage)")
        }
    }
    .store(in: &cancellables)
```

**UploadStage:**

| Case | Description |
|------|-------------|
| `.initialize` | Transaction initialized on server |
| `.stop` | Recording stop signaled to server |
| `.commit` | Chunks committed for processing |
| `.analyzing` | Server-side transcription in progress |
| `.completed` | Processing complete |
| `.failure` | Processing failed |
| `.error` | An error occurred |
| `.cancelled` | Session was cancelled |

---

## Getting Results

### Method 1: Via Delegate (Recommended)

Implement the optional `didCompleteSession` delegate method:

```swift
func scribe(_ scribe: EkaScribe, didCompleteSession sessionId: String, result: SessionResult) {
    for template in result.templates {
        print("Template: \(template.title ?? "")")
        for section in template.sections {
            print("  \(section.title ?? ""): \(section.value ?? "")")
        }
    }
}
```

### Method 2: Fetch On-Demand

```swift
let result = await EkaScribe.shared.getSessionOutput(sessionId)
switch result {
case .success(let sessionResult):
    for template in sessionResult.templates {
        print("Template: \(template.title ?? "")")
    }
case .failure(let error):
    print("Error: \(error)")
}
```

### Method 3: Poll Until Ready

```swift
let result = await EkaScribe.shared.pollSessionResult(sessionId)
switch result {
case .success(let sessionResult):
    // Transcription is ready
    print("Templates: \(sessionResult.templates.count)")
case .failure(let error):
    print("Polling failed: \(error)")
}
```

### Result Structure

**SessionResult:**

| Property | Type | Description |
|----------|------|-------------|
| `templates` | `[TemplateOutput]` | Generated template outputs |
| `audioQuality` | `Double?` | Overall audio quality score |

**TemplateOutput:**

| Property | Type | Description |
|----------|------|-------------|
| `name` | `String?` | Template name |
| `title` | `String?` | Template title |
| `sections` | `[SectionData]` | Structured content sections |
| `sessionId` | `String` | Associated session ID |
| `templateId` | `String?` | Template identifier |
| `isEditable` | `Bool` | Whether the output is editable |
| `type` | `TemplateType` | Output format (`.markdown`, `.json`, `.ekaEmr`) |
| `rawOutput` | `String?` | Raw output string |

**SectionData:**

| Property | Type | Description |
|----------|------|-------------|
| `title` | `String?` | Section title (e.g., "Subjective", "Assessment") |
| `value` | `String?` | Section content |

---

## Templates & Configuration

### Fetch Available Templates

```swift
let result = await EkaScribe.shared.getTemplates()
switch result {
case .success(let templates):
    for template in templates {
        print("\(template.title) (ID: \(template.id), favorite: \(template.isFavorite))")
    }
case .failure(let error):
    print("Error: \(error)")
}
```

### Update Favourite Templates

```swift
let result = await EkaScribe.shared.updateTemplates(favouriteTemplates: ["template-id-1", "template-id-2"])
```

### Convert Result to a Different Template

```swift
let result = await EkaScribe.shared.convertTransactionResult(sessionId, templateId: "new-template-id")
```

### Update Session Result

```swift
let updatedData = [
    SessionData(templateId: "template-id", data: "{\"sections\": [...]}")
]
let result = await EkaScribe.shared.updateSessionResult(sessionId, updatedData: updatedData)
```

### Fetch User Configuration

```swift
let result = await EkaScribe.shared.getUserConfigs()
switch result {
case .success(let configs):
    print("Modes: \(configs.consultationModes.modes.map { $0.name })")
    print("Languages: \(configs.supportedLanguages.languages.map { $0.name })")
    print("Templates: \(configs.outputTemplates.templates.map { $0.name })")
    print("Models: \(configs.modelConfigs.modelTypes.map { $0.name })")
case .failure(let error):
    print("Error: \(error)")
}
```

### Update User Preferences

```swift
let prefs = SelectedUserPreferences(
    consultationMode: ConsultationMode(id: "consultation", name: "Consultation", desc: ""),
    languages: [SupportedLanguage(id: "en-IN", name: "English (India)")],
    outputTemplates: [ConfigOutputTemplate(id: "soap", name: "SOAP Notes")],
    modelType: ModelType(id: "pro", name: "Pro", desc: "High accuracy")
)
let result = await EkaScribe.shared.updateUserConfigs(prefs)
```

---

## Session History & Retry

### Fetch Session History

```swift
// From server
let history = try await EkaScribe.shared.getHistory(count: 20)
for item in history {
    print("\(item.txnId ?? "") - \(item.processingStatus ?? "")")
}

// From local database
let sessions = try await EkaScribe.shared.getSessions()
for session in sessions {
    print("\(session.sessionId) - \(session.state) - \(session.uploadStage)")
}

// Specific session
let session = try await EkaScribe.shared.getSession("session-id")
```

### Retry a Failed Session

The SDK provides idempotent error recovery. Retrying picks up from the last successful stage:

```swift
let result = try await EkaScribe.shared.retrySession(sessionId)
switch result {
case .success(let folderName, let bid):
    print("Retry succeeded: \(folderName)")
case .error(let message, let code):
    print("Retry failed: \(message)")
}
```

Use `forceCommit: true` to force a commit even if chunks are still pending:

```swift
let result = try await EkaScribe.shared.retrySession(sessionId, forceCommit: true)
```

### Get Full Audio File

When `fullAudioOutput` is enabled in config:

```swift
if let audioURL = EkaScribe.shared.getFullAudioFile() {
    // Play or share the audio file
    print("Audio file: \(audioURL.path)")
}
```

---

## Audio Analyser

The SDK includes an on-device audio quality model that downloads automatically when `enableAnalyser` is `true`. Observe the download state via the `analyserState` published property:

```swift
EkaScribe.shared.$analyserState
    .receive(on: DispatchQueue.main)
    .sink { state in
        switch state {
        case .disabled:
            print("Analyser disabled")
        case .idle:
            print("Analyser idle")
        case .downloading(let percent):
            print("Downloading model: \(percent)%")
        case .ready(let path):
            print("Model ready at: \(path)")
        case .failed(let error):
            print("Model download failed: \(error)")
        }
    }
    .store(in: &cancellables)
```

| State | Description |
|-------|-------------|
| `.disabled` | Analyser is disabled in config |
| `.idle` | Ready but not yet active |
| `.downloading(progressPercent:)` | Model is being downloaded |
| `.ready(modelPath:)` | Model loaded and ready for inference |
| `.failed(error:)` | Model download or load failed |

---

## Error Handling

Errors are delivered as `ScribeError` objects via the delegate and as thrown errors from async methods.

```swift
public struct ScribeError: Error, Sendable {
    public let code: ErrorCode     // Error classification
    public let message: String     // Human-readable description
    public var isRecoverable: Bool // Whether the error can be retried
}
```

### Error Codes

| Code | Description |
|------|-------------|
| `micPermissionDenied` | Microphone permission was denied |
| `sessionAlreadyActive` | A session is already in progress |
| `invalidConfig` | SDK not initialized or invalid configuration |
| `encoderFailed` | Audio encoding (M4A) failed |
| `uploadFailed` | Chunk upload to S3 failed |
| `modelLoadFailed` | Audio quality model failed to load |
| `networkUnavailable` | No network connection available |
| `dbError` | Local database operation failed |
| `invalidStateTransition` | Invalid session state transition attempted |
| `initTransactionFailed` | Server transaction initialization failed |
| `stopTransactionFailed` | Server stop transaction failed |
| `commitTransactionFailed` | Server commit transaction failed |
| `pollTimeout` | Result polling timed out |
| `transcriptionFailed` | Server-side transcription failed |
| `recorderSetupFailed` | Audio recorder setup failed |
| `retryExhausted` | Maximum retry attempts exceeded |
| `txnLimitReached` | Transaction limit reached |
| `unknown` | An unknown error occurred |

### Error Handling in Delegate

```swift
func scribe(_ scribe: EkaScribe, didFailWithError error: ScribeError) {
    print("Error [\(error.code)]: \(error.message)")

    if error.isRecoverable {
        // Retry the session
        Task {
            let result = try await EkaScribe.shared.retrySession(sessionId)
        }
    }
}

func scribe(_ scribe: EkaScribe, didFailSession sessionId: String, error: ScribeError) {
    // Server-side processing failed
    print("Session \(sessionId) failed: \(error.message)")
}
```

### Session Events for Debugging

For fine-grained lifecycle tracking, implement the `didEmitEvent` delegate method:

```swift
func scribe(_ scribe: EkaScribe, didEmitEvent event: SessionEvent) {
    // event.eventType: .success, .error, .info
    // event.eventName: detailed event identifier (e.g., .chunkUploaded, .initTransactionFailed)
    // event.metadata: additional key-value context
    analytics.log(event.eventName.rawValue, metadata: event.metadata)
}
```

---

## Cleanup

Call `destroy()` when the SDK is no longer needed to release all resources:

```swift
EkaScribe.shared.destroy()
```

**Important:** Always call `destroy()` in your view controller's `deinit` or when navigating away from the recording screen to prevent memory leaks.

---

## API Reference Summary

### EkaScribe (Singleton)

| Method | Description |
|--------|-------------|
| `initialize(config:delegate:)` | Initialize the SDK (call once) |
| `startSession(config:onStart:onError:)` | Start a new recording session |
| `pauseSession()` | Pause active recording |
| `resumeSession()` | Resume paused recording |
| `stopSession()` | Stop recording, begin processing |
| `cancelSession()` | Cancel session without processing |
| `isRecording()` | Check if currently recording |
| `destroy()` | Release all SDK resources |

### Observation

| Method / Property | Returns |
|-------------------|---------|
| `getSessionState()` | `AnyPublisher<SessionState, Never>` |
| `getAudioQuality()` | `AnyPublisher<AudioQualityMetrics, Never>` |
| `getVoiceActivity()` | `AnyPublisher<VoiceActivityData, Never>` |
| `getUploadProgress(sessionId:)` | `AnyPublisher<UploadStage?, Never>` |
| `$analyserState` | `Published<AnalyserState>` |

### Data Retrieval

| Method | Description |
|--------|-------------|
| `getSessions()` | Get all local session records |
| `getSession(_:)` | Get a specific session by ID |
| `getSessionOutput(_:)` | Fetch transcription result |
| `pollSessionResult(_:)` | Poll until transcription is ready |
| `retrySession(_:forceCommit:)` | Retry a failed session |
| `getHistory(count:)` | Fetch session history from server |
| `getFullAudioFile()` | Get the full audio recording URL |

### Templates & Configuration

| Method | Description |
|--------|-------------|
| `getTemplates()` | Fetch available output templates |
| `updateTemplates(favouriteTemplates:)` | Update favourite templates |
| `convertTransactionResult(_:templateId:)` | Convert result to a different template |
| `updateSessionResult(_:updatedData:)` | Update session output data |
| `getUserConfigs()` | Fetch user configuration |
| `updateUserConfigs(_:)` | Update user preferences |

### Protocols

| Protocol | Purpose |
|----------|---------|
| `EkaScribeTokenStorage` | Authentication token management |
| `EkaScribeDelegate` | Session lifecycle callbacks |

### Key Types

| Type | Description |
|------|-------------|
| `EkaScribeConfig` | SDK configuration |
| `SessionConfig` | Per-session parameters |
| `SessionResult` | Transcription output |
| `TemplateOutput` | Individual template result |
| `ScribeError` | Error with code and message |
| `SessionEvent` | Fine-grained lifecycle event |
| `ScribeSession` | Local session record |
| `ScribeHistoryItem` | Server session history entry |

---

## License

EkaScribeSDK is released under the MIT License. See [LICENSE](LICENSE) for details.
