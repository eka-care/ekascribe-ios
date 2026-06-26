# Usage Guide

This guide walks through integrating EkaScribeSDK into an iOS app step by step, with complete Swift code examples. For installation instructions see [setup.md](setup.md). For the full type reference see [api-reference.md](api-reference.md).

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Step 1 — Implement EkaScribeTokenStorage](#step-1--implement-ekascribetokenstorage)
3. [Step 2 — Implement EkaScribeDelegate](#step-2--implement-ekascribedelegate)
4. [Step 3 — Initialize the SDK](#step-3--initialize-the-sdk)
5. [Step 4 — Configure and Start a Session](#step-4--configure-and-start-a-session)
6. [Step 5 — Pause, Resume, Stop, and Cancel](#step-5--pause-resume-stop-and-cancel)
7. [Observing Real-Time Data with Combine](#observing-real-time-data-with-combine)
8. [Handling Session Results](#handling-session-results)
9. [Error Handling](#error-handling)
10. [Session Retry](#session-retry)
11. [Templates and User Config](#templates-and-user-config)
12. [Session History](#session-history)
13. [Full Audio Output](#full-audio-output)
14. [Cleaning Up](#cleaning-up)

---

## Quick Start

Minimal working example — copy, fill in your token logic, and run.

```swift
import EkaScribeSDK
import Combine

class AppSDKManager: EkaScribeDelegate {
    private var cancellables = Set<AnyCancellable>()

    func setup() throws {
        let config = EkaScribeConfig(
            environment: .production,
            clientInfo: ScribeClientInfo(clientId: "my-app"),
            tokenStorage: MyTokenStorage()
        )
        try EkaScribe.shared.initialize(config: config, delegate: self)
    }

    func startRecording() async throws {
        try await EkaScribe.shared.startSession(
            config: SessionConfig(
                languages: ["en"],
                mode: "consultation",
                modelType: "pro"
            )
        )
    }

    func stopRecording() {
        EkaScribe.shared.stopSession()
    }

    // MARK: - EkaScribeDelegate

    func scribe(_ scribe: EkaScribe, didStartSession sessionId: String) {
        print("Recording started: \(sessionId)")
    }

    func scribe(_ scribe: EkaScribe, didStopSession sessionId: String, chunkCount: Int) {
        print("Stopped. \(chunkCount) chunks uploaded. Processing...")
    }

    func scribe(_ scribe: EkaScribe, didCompleteSession sessionId: String, result: SessionResult) {
        for template in result.templates {
            print("--- \(template.title ?? "Output") ---")
            for section in template.sections {
                print("\(section.title ?? ""): \(section.value ?? "")")
            }
        }
    }

    func scribe(_ scribe: EkaScribe, didFailWithError error: ScribeError) {
        print("Error [\(error.code)]: \(error.message)")
    }
}
```

---

## Step 1 — Implement EkaScribeTokenStorage

The SDK never manages credentials itself. You provide an implementation of `EkaScribeTokenStorage` that reads and writes tokens from wherever your app stores them (e.g., Keychain).

```swift
import EkaScribeSDK
import Security

final class KeychainTokenStorage: EkaScribeTokenStorage {

    private let accessKey = "ekascribe.accessToken"
    private let refreshKey = "ekascribe.refreshToken"

    func getAccessToken() -> String? {
        return read(key: accessKey)
    }

    func getRefreshToken() -> String? {
        return read(key: refreshKey)
    }

    func saveTokens(accessToken: String, refreshToken: String) {
        save(key: accessKey, value: accessToken)
        save(key: refreshKey, value: refreshToken)
    }

    func onSessionExpired() {
        // Delete stored tokens and redirect the user to your login screen
        delete(key: accessKey)
        delete(key: refreshKey)
        NotificationCenter.default.post(name: .sessionExpired, object: nil)
    }

    // MARK: - Keychain helpers

    private func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension Notification.Name {
    static let sessionExpired = Notification.Name("EkaScribeSessionExpired")
}
```

**Important:** `EkaScribeTokenStorage` must be `AnyObject` (a class, not a struct) and `Sendable`. Keychain operations are safe to call from any thread.

---

## Step 2 — Implement EkaScribeDelegate

`EkaScribeDelegate` has five **required** methods and seven **optional** methods (default empty implementations provided). You only need to implement what you use.

```swift
import EkaScribeSDK

extension MyViewController: EkaScribeDelegate {

    // MARK: Required

    func scribe(_ scribe: EkaScribe, didStartSession sessionId: String) {
        DispatchQueue.main.async {
            self.recordButton.setTitle("Stop", for: .normal)
            self.statusLabel.text = "Recording…"
        }
    }

    func scribe(_ scribe: EkaScribe, didPauseSession sessionId: String) {
        DispatchQueue.main.async { self.statusLabel.text = "Paused" }
    }

    func scribe(_ scribe: EkaScribe, didResumeSession sessionId: String) {
        DispatchQueue.main.async { self.statusLabel.text = "Recording…" }
    }

    func scribe(_ scribe: EkaScribe, didStopSession sessionId: String, chunkCount: Int) {
        DispatchQueue.main.async {
            self.statusLabel.text = "Processing \(chunkCount) chunks…"
        }
    }

    func scribe(_ scribe: EkaScribe, didFailWithError error: ScribeError) {
        DispatchQueue.main.async {
            self.showAlert(title: "Error", message: error.message)
        }
    }

    // MARK: Optional — transcript ready (faster, before templates)

    func scribe(_ scribe: EkaScribe, didReadyTranscript sessionId: String, result: SessionResult) {
        // The raw transcript is available; templates may still be processing.
        // Safe to start a new session now.
    }

    // MARK: Optional — full output ready

    func scribe(_ scribe: EkaScribe, didCompleteSession sessionId: String, result: SessionResult) {
        DispatchQueue.main.async {
            self.displayResult(result)
        }
    }

    // MARK: Optional — server-side processing failed

    func scribe(_ scribe: EkaScribe, didFailSession sessionId: String, error: ScribeError) {
        DispatchQueue.main.async {
            self.showAlert(title: "Transcription Failed", message: error.message)
        }
    }

    // MARK: Optional — phone call / headset disconnect

    func scribe(_ scribe: EkaScribe, didChangeAudioFocus hasFocus: Bool) {
        if !hasFocus {
            EkaScribe.shared.pauseSession()
        }
    }

    // MARK: Optional — fine-grained event log (useful for analytics)

    func scribe(_ scribe: EkaScribe, didEmitEvent event: SessionEvent) {
        Analytics.track(event.eventName.rawValue, properties: event.metadata)
    }
}
```

> **Thread safety:** All delegate callbacks are delivered on an internal SDK queue. Always dispatch UI updates back to `DispatchQueue.main`.

---

## Step 3 — Initialize the SDK

Call `initialize()` once — typically in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` or your root SwiftUI `App.init`. Calling it again before `destroy()` will throw.

```swift
import EkaScribeSDK

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    do {
        let config = EkaScribeConfig(
            environment: .production,           // .staging for QA, .dev for local testing
            clientInfo: ScribeClientInfo(
                clientId: "your-client-id"      // provided by Eka
            ),
            tokenStorage: KeychainTokenStorage(),
            sampleRate: .hz16000,               // 16 kHz recommended; matches backend expectations
            frameSize: .samples512,             // 512 samples (~32 ms at 16 kHz)
            enableAnalyser: true,               // download SQUIM model for audio quality scoring
            debugMode: false,                   // set true during development to log all HTTP traffic
            fullAudioOutput: false              // set true to save a WAV of the entire session
        )
        try EkaScribe.shared.initialize(config: config, delegate: self)
    } catch {
        print("EkaScribe init failed: \(error)")
    }
    return true
}
```

### Analyser state

When `enableAnalyser: true`, the SDK downloads the SQUIM ONNX model on first launch (~a few MB). You can observe its progress:

```swift
import Combine

var cancellables = Set<AnyCancellable>()

EkaScribe.shared.$analyserState
    .receive(on: DispatchQueue.main)
    .sink { state in
        switch state {
        case .idle:
            print("Analyser idle")
        case .downloading(let pct):
            print("Downloading model: \(pct)%")
        case .ready:
            print("Model ready")
        case .failed(let error):
            print("Model failed: \(error)")
        case .disabled:
            print("Analyser disabled")
        }
    }
    .store(in: &cancellables)
```

---

## Step 4 — Configure and Start a Session

### Basic session

```swift
let sessionConfig = SessionConfig(
    languages: ["en"],              // BCP-47 language codes; up to 2
    mode: "consultation",           // "consultation" or "dictation"
    modelType: "general"            // model tier; use "pro" for higher accuracy
)

try await EkaScribe.shared.startSession(config: sessionConfig)
```

### With output templates

```swift
let sessionConfig = SessionConfig(
    languages: ["en", "hi"],
    mode: "consultation",
    modelType: "pro",
    outputTemplates: [
        OutputTemplate(templateId: "soap", templateName: "SOAP Note"),
        OutputTemplate(templateId: "referral_letter", templateName: "Referral Letter")
    ]
)
```

### With patient context

```swift
let sessionConfig = SessionConfig(
    languages: ["en"],
    mode: "consultation",
    modelType: "pro",
    outputTemplates: [OutputTemplate(templateId: "soap")],
    patientDetails: PatientDetail(
        age: 45,
        biologicalSex: "male",      // "male", "female", or "other"
        name: "John Doe",
        patientId: "P12345",
        visitId: "V98765"
    )
)
```

### With onStart and onError closures

These closures fire synchronously before the delegate callbacks and are useful when calling from a SwiftUI button action.

```swift
try await EkaScribe.shared.startSession(
    config: sessionConfig,
    onStart: { sessionId in
        print("Session \(sessionId) started")
    },
    onError: { error in
        print("Failed to start: \(error.message)")
    }
)
```

---

## Step 5 — Pause, Resume, Stop, and Cancel

```swift
// Pause recording (frames stop flowing; session state → .paused)
EkaScribe.shared.pauseSession()

// Resume from pause (frames resume; session state → .recording)
EkaScribe.shared.resumeSession()

// Stop and process (uploads remaining chunks, calls stop/commit API, polls for result)
// Results arrive via delegate callbacks didReadyTranscript and didCompleteSession
EkaScribe.shared.stopSession()

// Cancel (aborts in-flight uploads, no server processing, session state → .idle)
EkaScribe.shared.cancelSession()

// Check if currently recording
let active = EkaScribe.shared.isRecording()
```

---

## Observing Real-Time Data with Combine

All publishers are hot streams — subscribe before starting a session to avoid missing events.

### Session state

```swift
try EkaScribe.shared.getSessionState()
    .receive(on: DispatchQueue.main)
    .sink { state in
        switch state {
        case .idle:       print("Idle")
        case .starting:   print("Starting…")
        case .recording:  print("Recording")
        case .paused:     print("Paused")
        case .stopping:   print("Stopping…")
        case .processing: print("Processing…")
        case .completed:  print("Done")
        case .error:      print("Error")
        }
    }
    .store(in: &cancellables)
```

### Voice activity (real-time waveform / mic indicator)

```swift
try EkaScribe.shared.getVoiceActivity()
    .receive(on: DispatchQueue.main)
    .sink { data in
        waveformView.amplitude = CGFloat(data.amplitude)    // 0.0 – 1.0 normalised RMS
        micIndicator.isActive = data.isSpeech               // true when speech detected
    }
    .store(in: &cancellables)
```

`VoiceActivityData` fields:
- `isSpeech: Bool` — libfvad classification for this frame.
- `amplitude: Float` — normalised RMS amplitude (0 = silence, 1 = clipping).
- `timestampMs: Int` — client-side timestamp in milliseconds.

### Audio quality metrics

Published approximately every 3 seconds while recording.

```swift
try EkaScribe.shared.getAudioQuality()
    .receive(on: DispatchQueue.main)
    .sink { metrics in
        qualityBar.progress = metrics.overallScore   // 0.0 – 1.0 composite score
        stoiLabel.text = String(format: "STOI: %.2f", metrics.stoi)
        pesqLabel.text = String(format: "PESQ: %.2f", metrics.pesq)
    }
    .store(in: &cancellables)
```

`AudioQualityMetrics` fields:
- `stoi: Float` — Short-Time Objective Intelligibility (0–1, higher is better).
- `pesq: Float` — Perceptual Evaluation of Speech Quality.
- `siSDR: Float` — Scale-Invariant Signal-to-Distortion Ratio.
- `overallScore: Float` — Composite score (0–1).

### Upload progress

```swift
try EkaScribe.shared.getUploadProgress(sessionId: currentSessionId)
    .receive(on: DispatchQueue.main)
    .sink { stage in
        switch stage {
        case .initialize: progressLabel.text = "Initialising…"
        case .stop:       progressLabel.text = "Uploading…"
        case .commit:     progressLabel.text = "Committing…"
        case .analyzing:  progressLabel.text = "Analysing…"
        case .completed:  progressLabel.text = "Done"
        case .failure, .error: progressLabel.text = "Upload failed"
        case .cancelled:  progressLabel.text = "Cancelled"
        case .none:       break
        }
    }
    .store(in: &cancellables)
```

---

## Handling Session Results

### Via delegate (recommended)

```swift
func scribe(_ scribe: EkaScribe, didCompleteSession sessionId: String, result: SessionResult) {
    for template in result.templates {
        print("Template: \(template.title ?? template.name ?? "unnamed")")
        print("Type: \(template.type)")          // .markdown, .json, .ekaEmr
        print("Editable: \(template.isEditable)")

        for section in template.sections {
            print("  \(section.title ?? ""): \(section.value ?? "")")
        }

        // Raw output string (base64-decoded by the SDK)
        if let raw = template.rawOutput {
            print("Raw: \(raw)")
        }
    }

    if let quality = result.audioQuality {
        print("Overall audio quality: \(quality)")
    }
}
```

### On-demand fetch

```swift
let result = await EkaScribe.shared.getSessionOutput(sessionId)
switch result {
case .success(let sessionResult):
    handleResult(sessionResult)
case .failure(let error):
    print("Fetch failed: \(error)")
}
```

### Built-in polling

Polls up to `pollMaxRetries` (default 3) times with `pollDelayMs` (default 2000 ms) between attempts.

```swift
let result = await EkaScribe.shared.pollSessionResult(sessionId)
switch result {
case .success(let sessionResult):
    handleResult(sessionResult)
case .failure(let error):
    print("Polling timed out or failed: \(error)")
}
```

### Convert to a different template

```swift
let result = await EkaScribe.shared.convertTransactionResult(sessionId, templateId: "referral_letter")
if case .success = result {
    // Fetch the converted output
    let updated = await EkaScribe.shared.getSessionOutput(sessionId)
}
```

### Update / edit a session result

```swift
let update = SessionData(
    templateId: "soap",
    documentId: template.documentId ?? "",
    data: editedJsonString     // your edited content as a JSON string
)
let result = await EkaScribe.shared.updateSessionResult(sessionId, updatedData: [update])
```

---

## Error Handling

All errors come through `didFailWithError` or as thrown errors / `Result.failure`.

```swift
func scribe(_ scribe: EkaScribe, didFailWithError error: ScribeError) {
    print("Code: \(error.code.rawValue)")
    print("Message: \(error.message)")
    print("Recoverable: \(error.isRecoverable)")

    if error.isRecoverable {
        Task {
            try? await EkaScribe.shared.retrySession(lastSessionId)
        }
    } else {
        showFatalError(error.message)
    }
}
```

### Error codes

| Code | Meaning | Recoverable? |
|------|---------|-------------|
| `micPermissionDenied` | Microphone access denied by user | No — direct user to Settings |
| `sessionAlreadyActive` | `startSession` called while a session is running | No |
| `invalidConfig` | SDK not initialized or config missing | No |
| `encoderFailed` | M4A encoding failed for a chunk | Possible |
| `uploadFailed` | S3 upload failed after retries | Yes — retry the session |
| `modelLoadFailed` | SQUIM ONNX model unavailable | No — analyser disabled for this session |
| `networkUnavailable` | No network connectivity | Yes |
| `dbError` | Local SQLite read/write error | Rare |
| `invalidStateTransition` | Illegal state change requested | No |
| `initTransactionFailed` | Backend init call failed | Yes |
| `stopTransactionFailed` | Backend stop call failed | Yes |
| `commitTransactionFailed` | Backend commit call failed | Yes |
| `pollTimeout` | Result polling exceeded retry limit | Yes |
| `transcriptionFailed` | Backend returned a failure status | Possibly |
| `recorderSetupFailed` | AVAudioEngine configuration error | No |
| `retryExhausted` | Recovery attempts exceeded the limit | No |
| `txnLimitReached` | Backend rate limit for transactions | Wait and retry |
| `unknown` | Unclassified error | Check `message` |

---

## Session Retry

If a session was interrupted (app backgrounded, network dropped, crash), you can resume it from the last successful stage without re-recording:

```swift
do {
    let result = try await EkaScribe.shared.retrySession(sessionId)
    switch result {
    case .success(let sessionResult):
        handleResult(sessionResult)
    case .failure(let error):
        print("Retry failed: \(error.message)")
    case .partialSuccess(let sessionResult):
        // Transcript ready, templates still processing
        handlePartialResult(sessionResult)
    }
} catch {
    print("Retry error: \(error)")
}
```

Set `forceCommit: true` to commit even if some chunks are still pending upload:

```swift
try await EkaScribe.shared.retrySession(sessionId, forceCommit: true)
```

**How it works:** `retrySession` reads the `uploadStage` from the local database and resumes from the first incomplete stage — it will not re-upload already-uploaded chunks.

---

## Templates and User Config

### Fetch available templates

```swift
let result = await EkaScribe.shared.getTemplates()
if case .success(let items) = result {
    for item in items {
        print("\(item.id): \(item.title) (default: \(item.isDefault), fav: \(item.isFavorite))")
    }
}
```

### Save favourite templates

```swift
let favouriteIds = ["soap", "referral_letter"]
let result = await EkaScribe.shared.updateTemplates(favouriteTemplates: favouriteIds)
```

### Fetch user configuration (modes, languages, templates)

```swift
let result = await EkaScribe.shared.getUserConfigs()
if case .success(let configs) = result {
    // Available consultation modes
    for mode in configs.consultationModes.modes {
        print("\(mode.id): \(mode.name)")
    }

    // Supported languages
    for lang in configs.supportedLanguages.languages {
        print("\(lang.id): \(lang.name)")
    }

    // Currently selected preferences
    print("Selected mode: \(configs.selectedUserPreferences.consultationMode?.name ?? "none")")
}
```

### Update user preferences

```swift
let prefs = SelectedUserPreferences(
    consultationMode: ConsultationMode(id: "gp", name: "General Practice", desc: ""),
    languages: [SupportedLanguage(id: "en", name: "English")],
    outputTemplates: [ConfigOutputTemplate(id: "soap", name: "SOAP Note")],
    modelType: ModelType(id: "pro", name: "Pro", desc: "")
)
let result = await EkaScribe.shared.updateUserConfigs(prefs)
```

---

## Session History

Fetch the server-side session history (most recent sessions processed by the backend):

```swift
do {
    let history = try await EkaScribe.shared.getHistory(count: 20)
    for item in history {
        print("\(item.txnId ?? "-"): \(item.processingStatus ?? "unknown") at \(item.createdAt ?? "-")")
        if let patient = item.patientDetails {
            print("  Patient: \(patient.name ?? "unknown")")
        }
    }
} catch {
    print("History fetch failed: \(error)")
}
```

For locally stored sessions (persisted in the on-device SQLite database):

```swift
let sessions = try await EkaScribe.shared.getSessions()
for session in sessions {
    print("\(session.sessionId): \(session.state) / \(session.uploadStage)")
}

// Or fetch a specific session
if let session = try await EkaScribe.shared.getSession(sessionId) {
    print("Chunks: \(session.chunkCount), Stage: \(session.uploadStage)")
}
```

---

## Full Audio Output

To capture the complete session audio as a single WAV file, enable `fullAudioOutput` in the SDK config:

```swift
let config = EkaScribeConfig(
    environment: .production,
    clientInfo: ScribeClientInfo(clientId: "my-app"),
    tokenStorage: tokenStorage,
    fullAudioOutput: true       // enable full audio capture
)
```

After `stopSession()` completes (you receive `didStopSession`), retrieve the file URL:

```swift
func scribe(_ scribe: EkaScribe, didStopSession sessionId: String, chunkCount: Int) {
    if let audioURL = EkaScribe.shared.getFullAudioFile() {
        // Share, play back, or upload the WAV file
        let activityVC = UIActivityViewController(activityItems: [audioURL], applicationActivities: nil)
        present(activityVC, animated: true)
    }
}
```

The file is stored at:
```
{appSupportDirectory}/EkaScribeSDK/output/{sessionId}_full.wav
```

---

## Cleaning Up

Call `destroy()` when you no longer need the SDK — for example, on logout. This releases all internal resources.

```swift
EkaScribe.shared.destroy()
```

After `destroy()`, you must call `initialize()` again before using any SDK method.

---

## Complete Integration Example (SwiftUI)

```swift
import SwiftUI
import EkaScribeSDK
import Combine

@MainActor
class RecordingViewModel: ObservableObject, EkaScribeDelegate {
    @Published var sessionState: SessionState = .idle
    @Published var amplitude: Float = 0
    @Published var isSpeaking = false
    @Published var result: SessionResult?
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        do {
            let config = EkaScribeConfig(
                environment: .production,
                clientInfo: ScribeClientInfo(clientId: "my-app"),
                tokenStorage: KeychainTokenStorage(),
                enableAnalyser: true
            )
            try EkaScribe.shared.initialize(config: config, delegate: self)
            subscribeToStreams()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func subscribeToStreams() {
        try? EkaScribe.shared.getSessionState()
            .receive(on: DispatchQueue.main)
            .assign(to: \.sessionState, on: self)
            .store(in: &cancellables)

        try? EkaScribe.shared.getVoiceActivity()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.amplitude = data.amplitude
                self?.isSpeaking = data.isSpeech
            }
            .store(in: &cancellables)
    }

    func startRecording() {
        Task {
            try await EkaScribe.shared.startSession(
                config: SessionConfig(
                    languages: ["en"],
                    mode: "consultation",
                    modelType: "general",
                    outputTemplates: [OutputTemplate(templateId: "soap", templateName: "SOAP Note")]
                )
            )
        }
    }

    func stopRecording() {
        EkaScribe.shared.stopSession()
    }

    // MARK: - EkaScribeDelegate

    nonisolated func scribe(_ scribe: EkaScribe, didStartSession sessionId: String) {}
    nonisolated func scribe(_ scribe: EkaScribe, didPauseSession sessionId: String) {}
    nonisolated func scribe(_ scribe: EkaScribe, didResumeSession sessionId: String) {}
    nonisolated func scribe(_ scribe: EkaScribe, didStopSession sessionId: String, chunkCount: Int) {}

    nonisolated func scribe(_ scribe: EkaScribe, didFailWithError error: ScribeError) {
        Task { @MainActor in self.errorMessage = error.message }
    }

    nonisolated func scribe(_ scribe: EkaScribe, didCompleteSession sessionId: String, result: SessionResult) {
        Task { @MainActor in self.result = result }
    }
}

struct RecordingView: View {
    @StateObject private var vm = RecordingViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Text(vm.sessionState.rawValue.capitalized)
                .font(.headline)

            // Waveform indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(vm.isSpeaking ? Color.green : Color.gray)
                .frame(width: 8, height: CGFloat(vm.amplitude) * 100 + 4)
                .animation(.easeOut(duration: 0.05), value: vm.amplitude)

            Button(vm.sessionState == .recording ? "Stop" : "Record") {
                if vm.sessionState == .recording {
                    vm.stopRecording()
                } else {
                    vm.startRecording()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled([.starting, .stopping, .processing].contains(vm.sessionState))

            if let result = vm.result {
                ScrollView {
                    ForEach(result.templates.indices, id: \.self) { i in
                        let template = result.templates[i]
                        VStack(alignment: .leading) {
                            Text(template.title ?? "Output")
                                .font(.title3).bold()
                            ForEach(template.sections.indices, id: \.self) { j in
                                let section = template.sections[j]
                                VStack(alignment: .leading) {
                                    Text(section.title ?? "").font(.caption).foregroundColor(.secondary)
                                    Text(section.value ?? "")
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .padding()
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}
```
