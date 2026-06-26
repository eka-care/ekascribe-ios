# Project Setup Guide

This document covers everything needed to integrate EkaScribeSDK into an iOS app or to set up a local development environment for contributing to the SDK itself.

---

## Prerequisites

| Requirement | Minimum Version | Notes |
|-------------|----------------|-------|
| Xcode | 15.0+ | Required for Swift 5.10 support |
| Swift | 5.10+ | Specified in `Package.swift` |
| iOS Deployment Target | 15.0+ | SDK uses async/await and Combine |
| macOS (development machine) | Ventura 13.0+ | Recommended for Xcode 15 |

---

## Installing the SDK

### Option A — Xcode Package Manager UI

1. Open your project in Xcode.
2. Go to **File → Add Package Dependencies…**
3. Enter the repository URL:
   ```
   https://github.com/eka-care/ekascribe-ios.git
   ```
4. Set the dependency rule to **Up to Next Major Version** starting from `0.1.0`.
5. Select the **EkaScribeSDK** library and click **Add to Target**.

### Option B — Package.swift

Add the SDK as a dependency in your own Swift package:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/eka-care/ekascribe-ios.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "EkaScribeSDK", package: "ekascribe-ios")
        ]
    )
]
```

---

## Required App Permissions

### Microphone (required)

Add the following key to your app's `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Required for medical transcription recording</string>
```

The SDK checks microphone permission at the start of every session. If permission is denied or undetermined and the user does not grant it at the system prompt, `startSession` will deliver a `ScribeError` with code `.micPermissionDenied` via the `onError` callback.

There are no additional entitlements or capabilities required.

---

## SDK Dependencies

The SDK pulls in the following packages automatically via SPM. You do not need to add them manually.

| Package | Version | Purpose |
|---------|---------|---------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | master | Local SQLite persistence for sessions and audio chunks |
| [aws-sdk-ios-spm](https://github.com/aws-amplify/aws-sdk-ios-spm) | ≥ 2.36.6 | AWS S3 multipart uploads for audio chunks |
| [libfvad](https://github.com/gfreezy/libfvad) | main | On-device Voice Activity Detection (WebRTC) |
| [Alamofire](https://github.com/Alamofire/Alamofire) | ≥ 5.10.2 | HTTP networking and auth interceptor |
| [swift-atomics](https://github.com/apple/swift-atomics) | ≥ 1.2.0 | Lock-free atomic operations for the audio PreBuffer |

> **Note:** The ONNX Runtime dependency (`onnxruntime-swift-package-manager`) is commented out in `Package.swift`. The audio quality analyser currently uses a locally downloaded ONNX model file managed by `ModelDownloader` at runtime.

---

## Environments

The SDK supports three backend environments, selected via `EkaScribeConfig.environment`:

| Environment | Base API URL | Credentials URL | S3 Bucket |
|-------------|-------------|-----------------|-----------|
| `.production` | `https://api.eka.care` | `https://cog.eka.care/credentials` | `m-prod-voice-record` |
| `.staging` | `https://api.staging.eka.care` | `https://cog.staging.eka.care/credentials` | `m-staging-voice-record` |
| `.dev` | `https://api.dev.eka.care` | `https://cog.dev.eka.care/credentials` | `m-dev-voice-record` |

The default environment is `.production`. Use `.staging` or `.dev` for testing and development.

```swift
let config = EkaScribeConfig(
    environment: .staging,   // switch environment here
    clientInfo: ScribeClientInfo(clientId: "your-client-id"),
    tokenStorage: yourTokenStorage
)
```

---

## Authentication

The SDK does not manage credentials — it delegates to your app via the `EkaScribeTokenStorage` protocol. You must provide:

- An **access token** (Bearer token for the Eka API).
- A **refresh token** used to obtain a new access token when the current one expires.

Token refresh is handled automatically by the SDK's `AuthInterceptor` on 401 responses. The refresh endpoint used is:

```
POST {baseURL}/connect-auth/v1/account/refresh-token
```

See [usage-guide.md](usage-guide.md#step-1--implement-ekaScribeTokenStorage) for an implementation example.

---

## SDK Configuration Reference

```swift
let config = EkaScribeConfig(
    environment: .production,       // target environment (default: .production)
    clientInfo: ScribeClientInfo(
        clientId: "your-client-id", // identifies your app to the backend
        flavour: "ScribeIOS"        // optional; default: "ScribeIOS"
    ),
    tokenStorage: yourTokenStorage, // required: your EkaScribeTokenStorage impl
    sampleRate: .hz16000,           // audio sample rate (default: .hz16000)
    frameSize: .samples512,         // samples per audio frame (default: .samples512)
    enableAnalyser: true,           // download and run SQUIM quality model (default: true)
    debugMode: false,               // log requests/responses to console (default: false)
    fullAudioOutput: false          // save full session audio as a WAV file (default: false)
)
```

**Hardcoded pipeline limits** (not configurable at the `EkaScribeConfig` level):

| Parameter | Value | Description |
|-----------|-------|-------------|
| `preferredChunkDurationSec` | 10 s | Target chunk length |
| `desperationChunkDurationSec` | 20 s | Force-cut at this length if silence not found |
| `maxChunkDurationSec` | 25 s | Absolute maximum chunk length |
| `overlapDurationSec` | 0.5 s | Overlap between consecutive chunks |
| `maxUploadRetries` | 2 | Retries per chunk S3 upload |
| `pollMaxRetries` | 3 | Polling attempts for transcription result |
| `pollDelayMs` | 2000 ms | Delay between poll attempts |

---

## Contributing to the SDK

### Clone the repository

```bash
git clone https://github.com/eka-care/ekascribe-ios.git
cd ekascribe-ios
```

### Open in Xcode

```bash
open Package.swift
```

Xcode will resolve dependencies automatically.

### Build

```bash
swift build
```

### Run the test suite

```bash
swift test
```

The test suite has 36 test files covering all major modules. Tests are purely unit tests and run without a device or simulator.

### Project structure overview

```
ekascribe-ios/
├── Sources/EkaScribeSDK/    # All SDK source (105 Swift files)
├── Tests/EkaScribeSDKTests/ # Unit tests (36 Swift files)
├── knowledge/               # Internal ADRs and iteration notes
├── docs/                    # This documentation folder
├── Package.swift            # SPM manifest
└── README.md                # Repository overview
```

See [architecture.md](architecture.md) for a detailed breakdown of the `Sources/` directory.

---

## Build Configuration Notes

- **Debug builds**: `debugMode: true` in `EkaScribeConfig` enables the `DefaultLogger`, which prints all HTTP request/response details and SDK state changes to the Xcode console.
- **Release builds**: Use `debugMode: false` (the default) to use `NoOpLogger`, which produces no console output.
- **Full audio output**: Set `fullAudioOutput: true` during development if you need to inspect the complete raw audio for a session. The WAV file is written to `{appSupport}/EkaScribeSDK/output/{sessionId}_full.wav`.
- **Analyser model**: When `enableAnalyser: true`, the SDK downloads an ONNX model (~few MB) on first launch and caches it in `{appSupport}/EkaScribeSDK/models/`. Subsequent launches use ETag-based HTTP caching (HTTP 304) to avoid re-downloading.
