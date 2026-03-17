# EkaScribeSDK

[![Swift](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015%2B%20%7C%20macOS%2012%2B-blue.svg)](https://developer.apple.com)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager)
[![License](https://img.shields.io/badge/License-MIT-lightgray.svg)](LICENSE)

A Swift SDK for real-time audio recording, chunked upload, and AI-powered medical transcription.

## Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 15.0+          |
| macOS    | 12.0+          |
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

## Quick Start

### 1. Implement Token Storage

```swift
import EkaScribeSDK

class MyTokenStorage: EkaScribeTokenStorage {
    func getAccessToken() -> String? { /* return stored access token */ }
    func getRefreshToken() -> String? { /* return stored refresh token */ }
    func saveTokens(accessToken: String, refreshToken: String) { /* persist tokens */ }
    func onSessionExpired() { /* handle session expiration */ }
}
```

### 2. Implement the Delegate

```swift
class MyScribeDelegate: EkaScribeDelegate {
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
        print("Error: \(error.message)")
    }
}
```

### 3. Initialize the SDK

```swift
let config = EkaScribeConfig(
    environment: .production,
    clientInfo: ScribeClientInfo(clientId: "your-client-id"),
    tokenStorage: MyTokenStorage()
)

try EkaScribe.shared.initialize(config: config, delegate: MyScribeDelegate())
```

### 4. Start a Recording Session

```swift
let sessionConfig = SessionConfig(
    languages: ["en"],
    mode: "consultation",
    modelType: "default"
)

try await EkaScribe.shared.startSession(
    config: sessionConfig,
    onStart: { sessionId in
        print("Recording started: \(sessionId)")
    },
    onError: { error in
        print("Failed: \(error.message)")
    }
)
```

### 5. Control the Session

```swift
// Pause recording
EkaScribe.shared.pauseSession()

// Resume recording
EkaScribe.shared.resumeSession()

// Stop and process
EkaScribe.shared.stopSession()

// Cancel without processing
EkaScribe.shared.cancelSession()
```

### 6. Observe Session State

```swift
import Combine

var cancellables = Set<AnyCancellable>()

try EkaScribe.shared.getSessionState()
    .sink { state in
        // .idle, .starting, .recording, .paused, .stopping, .processing, .completed, .error
        print("State: \(state)")
    }
    .store(in: &cancellables)
```

### 7. Get Transcription Results

```swift
let result = await EkaScribe.shared.getSessionOutput(sessionId)
switch result {
case .success(let sessionResult):
    print("Templates: \(sessionResult.templates)")
case .failure(let error):
    print("Error: \(error)")
}
```

### 8. Clean Up

```swift
EkaScribe.shared.destroy()
```

## API Overview

### Core Types

| Type | Description |
|------|-------------|
| `EkaScribe` | Main SDK singleton accessed via `EkaScribe.shared` |
| `EkaScribeConfig` | SDK configuration (environment, client info, token storage) |
| `EkaScribeDelegate` | Protocol for session lifecycle callbacks |
| `EkaScribeTokenStorage` | Protocol for authentication token management |
| `SessionConfig` | Per-session parameters (languages, mode, model type) |

### Session Lifecycle

| Method | Description |
|--------|-------------|
| `initialize(config:delegate:)` | Initialize the SDK (call once) |
| `startSession(config:onStart:onError:)` | Start a new recording session |
| `pauseSession()` | Pause the active recording |
| `resumeSession()` | Resume a paused recording |
| `stopSession()` | Stop recording and begin processing |
| `cancelSession()` | Cancel the session without processing |
| `destroy()` | Release all SDK resources |

### Observation (Combine Publishers)

| Method | Returns |
|--------|---------|
| `getSessionState()` | `AnyPublisher<SessionState, Never>` |
| `getAudioQuality()` | `AnyPublisher<AudioQualityMetrics, Never>` |
| `getVoiceActivity()` | `AnyPublisher<VoiceActivityData, Never>` |
| `getUploadProgress(sessionId:)` | `AnyPublisher<UploadStage?, Never>` |

### Data Retrieval

| Method | Description |
|--------|-------------|
| `getSessions()` | Get all local session records |
| `getSession(_:)` | Get a specific session by ID |
| `getSessionOutput(_:)` | Fetch transcription result |
| `pollSessionResult(_:)` | Poll until transcription is ready |
| `retrySession(_:forceCommit:)` | Retry a failed session upload |
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

### Key Enums

| Type | Values |
|------|--------|
| `SessionState` | `idle`, `starting`, `recording`, `paused`, `stopping`, `processing`, `completed`, `error` |
| `UploadStage` | `initialize`, `stop`, `commit`, `analyzing`, `completed`, `failure`, `error`, `cancelled` |
| `AnalyserState` | `disabled`, `idle`, `downloading`, `ready`, `failed` |

## Microphone Permission

Add the following key to your app's `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Required for medical transcription recording</string>
```

## License

EkaScribeSDK is released under the MIT License. See [LICENSE](LICENSE) for details.
