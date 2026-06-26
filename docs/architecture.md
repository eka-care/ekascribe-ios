# Architecture Guide

This document is for developers contributing to or extending EkaScribeSDK. It explains how the codebase is organized, how data flows through the system, and the key design decisions made.

---

## What the SDK Does

EkaScribeSDK turns a microphone tap into structured clinical documents:

1. Captures raw PCM audio frames from `AVAudioEngine`.
2. Detects speech silence boundaries using on-device VAD (libfvad) and splits audio into chunks (~10 s each).
3. Encodes each chunk to M4A (AAC via `AVAssetExportSession`).
4. Uploads each encoded chunk to AWS S3 in parallel, fire-and-forget.
5. When the session stops, signals the backend to begin transcription (init → stop → commit API calls).
6. Polls the backend for the transcription result and delivers it via delegate callbacks and Combine publishers.

---

## Repository Layout

```
ekascribe-ios/
├── Sources/EkaScribeSDK/
│   ├── API/            Public interface: EkaScribe singleton, config, delegate, token storage, models
│   ├── Session/        Session state machine, transaction lifecycle, event emitter
│   ├── Pipeline/       Audio processing orchestration (the hot path)
│   ├── Recorder/       AVAudioEngine tap, format conversion, audio focus handling
│   ├── Chunker/        libfvad wrapper, VAD-based audio segmentation
│   ├── Analyser/       SQUIM ONNX model, model downloader, audio quality scoring
│   ├── Encoder/        PCM → CAF → M4A (two-step), WAV fallback
│   ├── Data/
│   │   ├── Local/      GRDB SQLite schema, migrations, session and chunk records
│   │   └── Remote/     Alamofire HTTP client, auth interceptor, S3 uploader, API endpoints
│   └── Common/         Logger, AsyncSemaphore, NetworkMonitor, ErrorCode, utilities
├── Tests/EkaScribeSDKTests/   36 unit test files, one per module
├── knowledge/                 Internal ADRs and iteration notes (not for external readers)
└── docs/                      This documentation
```

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  Public API Layer                                               │
│  EkaScribe (singleton)  ·  EkaScribeDelegate  ·  EkaScribeConfig│
│  EkaScribeTokenStorage  ·  Public Models (API/Models/)          │
├─────────────────────────────────────────────────────────────────┤
│  Session & Transaction Layer                                    │
│  SessionManager  ·  TransactionManager  ·  SessionEventEmitter  │
├─────────────────────────────────────────────────────────────────┤
│  Pipeline Layer (Audio Hot Path)                                │
│  Pipeline  ·  FrameProducer  ·  PreBuffer  ·  ChunkUpload       │
│  Coordinator                                                    │
├─────────────────────────────────────────────────────────────────┤
│  Component Layer                                                │
│  IOSAudioRecorder  ·  VadAudioChunker  ·  SquimAudioAnalyser    │
│  M4aAudioEncoder   ·  S3ChunkUploader                          │
├─────────────────────────────────────────────────────────────────┤
│  Data Layer                                                     │
│  DefaultDataManager (GRDB)  ·  ScribeAPIService (Alamofire)     │
│  S3CredentialProvider       ·  AuthInterceptor                  │
├─────────────────────────────────────────────────────────────────┤
│  Common / Infrastructure                                        │
│  Logger  ·  AsyncSemaphore  ·  NetworkMonitor  ·  ErrorCode     │
│  IdGenerator  ·  TimeProvider  ·  FileUtils                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Module Descriptions

### `API/`

The only public surface of the SDK.

- **`EkaScribe.swift`** — Singleton (`EkaScribe.shared`). Wires up all internal components during `initialize()` and exposes the complete public API. Has no business logic of its own; it delegates everything to `SessionManager`, `TransactionManager`, `ScribeAPIService`, and `DataManager`.
- **`EkaScribeConfig.swift`** — Value type carrying environment, audio settings, and hardcoded pipeline limits.
- **`EkaScribeDelegate.swift`** — Protocol for lifecycle callbacks. Five methods are required; seven have default empty implementations in a `public extension`.
- **`EkaScribeTokenStorage.swift`** — Protocol for token management. The SDK calls `getAccessToken()` on each request and `saveTokens()` after a token refresh.
- **`Models/`** — All public data types. Structs and enums marked `Sendable` for safe cross-actor use.

### `Session/`

- **`SessionManager.swift`** — Owns the `CurrentValueSubject<SessionState>` state machine. Starts and stops `Pipeline`, calls `TransactionManager` for API handshaking, maps server responses to `SessionResult`, and fires all delegate callbacks. The `stop()` flow is a two-phase async operation: it first polls for a quick transcript result, then polls for full template output.
- **`TransactionManager.swift`** — Manages the three-step server handshake (init → stop → commit) and result polling. Also implements `checkAndProgress()` for idempotent session recovery.
- **`SessionEventEmitter.swift`** — Emits granular `SessionEvent` values for observability and debugging.
- **`MicPermissionChecker.swift`** — Checks and requests `AVAudioSession` microphone permission; handles the iOS 17 API split.

### `Pipeline/`

The hot path. Designed for low-latency, non-blocking operation.

- **`Pipeline.swift`** — Creates and coordinates three concurrent async `Task` loops:
  1. **Chunking loop**: feeds audio frames from the `AsyncStream` into `VadAudioChunker`.
  2. **Persistence loop**: takes completed `AudioChunk` values, runs the analyser, encodes to M4A, persists the `AudioChunkRecord` to GRDB, and submits to `ChunkUploadCoordinator` (fire-and-forget).
  3. **Quality forward loop**: pushes audio quality metrics from the analyser into the chunker so chunk records carry quality scores.
- **`FrameProducer.swift`** — Drains `PreBuffer` every 5 ms and yields batches of `AudioFrame` values to an `AsyncStream`. Supports pause/resume without losing frames.
- **`PreBuffer.swift`** — Lock-free circular ring buffer backed by `ManagedAtomic<Int>` (swift-atomics). Absorbs frame bursts from the AVAudioEngine tap without blocking the audio thread.
- **`ChunkUploadCoordinator.swift`** — Accepts submitted chunks and uploads them in background `Task` instances bounded by an `AsyncSemaphore` (capacity 10). Callers return immediately; `drain()` awaits all in-flight tasks before `Pipeline.stop()` returns.

### `Recorder/`

- **`IOSAudioRecorder.swift`** — Installs an `AVAudioEngine` tap and converts the hardware format (variable sample rate, possibly stereo) to the configured target format (e.g., 16 kHz mono Int16) via `AVAudioConverter`. Handles audio session interruptions and route changes by recreating the converter and emitting an `audioFocusChanged` event.
- **`RecorderConfig.swift`** — Carries sample rate and frame size for the recorder setup.
- **`AudioFrame.swift`** — Holds a `[Int16]` PCM buffer, a client-side `timestampMs`, `sampleRate`, and `frameIndex`.

### `Chunker/`

- **`VadAudioChunker.swift`** — Accumulates frames and calls `LibfvadProvider` for speech detection. Creates a new chunk when any of three conditions are met:
  - ≥ 10 s of audio AND ≥ 0.5 s of silence (preferred cut)
  - ≥ 20 s of audio AND ≥ 0.1 s of silence (desperation cut)
  - ≥ 25 s of audio regardless of speech (force cut)
  Also emits `VoiceActivityData` per frame for the UI.
- **`LibfvadProvider.swift`** — Thin Swift wrapper around the C `libfvad` library. Processes audio in 20 ms sub-frames (320 samples at 16 kHz) and returns `VadResult(isSpeech: Bool, confidence: Float)`.

### `Analyser/`

- **`SquimAudioAnalyser.swift`** — Accumulates frames, runs the SQUIM ONNX model every 3 seconds on a background thread, and publishes `AudioQuality` metrics (STOI, PESQ, SI-SDR). If the model is unavailable, `NoOpAudioAnalyser` is used instead.
- **`ModelDownloader.swift`** — Downloads and caches the SQUIM ONNX model file to `{appSupport}/EkaScribeSDK/models/squim_objective.onnx`. Uses ETag-based HTTP caching (sends `If-None-Match`; handles 304). Publishes `AnalyserState` as a `@Published` property.

### `Encoder/`

- **`M4aAudioEncoder.swift`** — Two-step encoding:
  1. Write `[Int16]` PCM → temporary `.caf` file using `AVAudioFile`.
  2. Convert `.caf` → `.m4a` using `AVAssetExportSession` with `AVAssetExportPresetAppleM4A`.
  Falls back to WAV if M4A export fails. Deletes the temporary `.caf` after conversion.
- **`EncodedChunk.swift`** — Carries the output file URL, duration in ms, and sample count.

### `Data/Local/`

- **`ScribeDatabase.swift`** — Creates and migrates the GRDB `DatabasePool` at `{appSupport}/EkaScribeSDK/eka_scribe.sqlite`. Runs schema migrations on every launch; erases the database if the schema version changes.
- **`SessionRecord.swift`** — GRDB `Record` for the `scribe_session` table.
- **`AudioChunkRecord.swift`** — GRDB `Record` for the `scribe_audio_chunk` table.

### `Data/Remote/`

- **`ScribeNetworkClient.swift`** — Wraps an Alamofire `Session` configured with `AuthInterceptor` and `APILogger`. Exposes `request()` and `requestAbsolute()` methods that return a `NetworkResult<T>` enum.
- **`ScribeAPIService.swift`** — Calls each REST endpoint and returns typed `NetworkResult` values. All methods are `async`.
- **`AuthInterceptor.swift`** — `RequestInterceptor` that injects `Authorization: Bearer {token}` and `client-id` headers on every request. On 401, retries token refresh via `POST /connect-auth/v1/account/refresh-token`, saves the new tokens, and retries the original request. Calls `tokenStorage.onSessionExpired()` if refresh fails.
- **`S3ChunkUploader.swift`** — Uses `AWSS3TransferUtility` to upload chunk files. Fetches temporary AWS credentials from `S3CredentialProvider` before each upload. Retries up to `maxRetryCount` times with exponential backoff.
- **`ScribeEndpoint.swift`** — `RequestProvider` enum listing all API paths and their HTTP methods.

### `Common/`

- **`AsyncSemaphore.swift`** — An `async/await`-compatible semaphore backed by an actor. Used by `ChunkUploadCoordinator` to cap concurrent uploads.
- **`DefaultLogger.swift` / `NoOpLogger.swift`** — `Logger` protocol implementations. `DefaultLogger` prints to stdout with a timestamp prefix; `NoOpLogger` discards everything.
- **`ErrorCode.swift`** — Enum of all SDK error cases. See [api-reference.md](api-reference.md#scribeerror--errorcode).
- **`NetworkMonitor.swift`** — Wraps `NWPathMonitor` to track network availability. `S3ChunkUploader` waits for connectivity before retrying a failed upload.

---

## Session State Machine

```
         ┌──────────────────────────────────────────────────────┐
         │                                                      │
  ┌──────▼──────┐  startSession()  ┌──────────────┐            │
  │    idle     │────────────────► │   starting   │            │
  └─────────────┘                  └──────┬───────┘            │
                                          │ AVAudioEngine       │
                                          │ running             │
                                          ▼                     │
                                   ┌──────────────┐            │
                           ┌──────►│  recording   │◄──┐        │
                           │       └──────┬───────┘   │        │
                           │resumeSession │pauseSession│        │
                           │              ▼            │        │
                           │       ┌──────────────┐   │        │
                           └───────│    paused    │───┘        │
                                   └──────┬───────┘            │
                                          │ stopSession()       │
                                          ▼                     │
                                   ┌──────────────┐            │
                                   │   stopping   │            │
                                   └──────┬───────┘            │
                                          │ pipeline drained    │
                                          ▼                     │
                                   ┌──────────────┐            │
                                   │  processing  │            │
                                   └──────┬───────┘            │
                                          │ result received     │
                                          ▼                     │
                                   ┌──────────────┐            │
                                   │  completed   │────────────┘
                                   └─────────────-┘
                                          │  (also from any state)
                                          ▼
                                   ┌──────────────┐
                                   │    error     │────► idle
                                   └──────────────┘
```

State transitions are validated by `SessionState.canTransition(to:)`. An invalid transition is logged and the session moves to `.error`.

---

## Audio Pipeline Data Flow

```
  AVAudioEngine tap
        │  [Int16] PCM frames @ frameSize (512 samples default)
        ▼
   PreBuffer  ←──── lock-free circular ring buffer (handles bursts)
        │
        ▼
  FrameProducer  ←──── drains every 5 ms → AsyncStream<AudioFrame>
        │
        ├──── raw PCM also written to disk as {sessionId}_raw.pcm
        │
        ▼
  VadAudioChunker  ←──── libfvad per-frame speech detection
        │  when chunk boundary detected (silence / duration limit)
        ▼
  SquimAudioAnalyser  ←──── scores chunk quality (STOI/PESQ/SI-SDR)
        │  AudioChunk with optional AudioQuality
        ▼
  M4aAudioEncoder  ←──── PCM Int16 → CAF → M4A (AVAssetExportSession)
        │  EncodedChunk (URL, durationMs)
        ▼
  DefaultDataManager  ←──── persists AudioChunkRecord to GRDB
        │
        ▼
  ChunkUploadCoordinator  ←──── fire-and-forget Task with AsyncSemaphore
        │
        ▼
  S3ChunkUploader  ←──── AWSS3TransferUtility with temporary credentials
        │
        ▼
  AWS S3 bucket  (s3://{bucket}/{folderName}/{sessionId}/{chunkId}.m4a)
```

---

## Two-Phase Transcription Polling

After `stop()` drains all uploads and sends the stop/commit API calls, `SessionManager` polls in two phases:

**Phase 1 — Transcript poll** (template ID = `"transcript"`)
- Faster; the backend generates a raw transcript before running template formatting.
- On success: fires `didReadyTranscript`, transitions session to `.completed` so the app can start a new session immediately.

**Phase 2 — Full output poll** (template ID = `nil`)
- Waits for all requested output templates to be ready.
- On success: fires `didReadyOutput`, then `didCompleteSession` with the full `SessionResult`.
- If Phase 1 timed out, Phase 2 continues regardless.

---

## Database Schema

### `scribe_session`

| Column | Type | Notes |
|--------|------|-------|
| `sessionId` | TEXT PK | UUID generated by the SDK |
| `createdAt` | INTEGER | Unix epoch ms |
| `updatedAt` | INTEGER | Unix epoch ms |
| `state` | TEXT | `SessionState` raw value |
| `chunkCount` | INTEGER | Number of audio chunks recorded |
| `mode` | TEXT | e.g. `"consultation"`, `"dictation"` |
| `uploadStage` | TEXT | `UploadStage` raw value (e.g. `"INIT"`, `"STOP"`, `"COMMIT"`, `"ANALYZING"`, `"COMPLETED"`) |
| `folderName` | TEXT | S3 folder prefix |
| `bid` | TEXT | Transaction ID returned by the backend |
| `sessionMetadata` | TEXT | JSON metadata blob |

### `scribe_audio_chunk`

| Column | Type | Notes |
|--------|------|-------|
| `chunkId` | TEXT PK | `{sessionId}_{chunkIndex}` |
| `sessionId` | TEXT FK | References `scribe_session.sessionId` |
| `chunkIndex` | INTEGER | Zero-based sequence number |
| `filePath` | TEXT | Local path to the encoded M4A file |
| `fileName` | TEXT | S3 object key |
| `startTimeMs` | INTEGER | Chunk start, relative to session start |
| `endTimeMs` | INTEGER | Chunk end time |
| `durationMs` | INTEGER | Chunk duration |
| `uploadState` | TEXT | `pending` / `inProgress` / `success` / `failed` |
| `qualityScore` | REAL | `AudioQuality.overallScore` (nullable) |
| `createdAt` | INTEGER | Unix epoch ms |

---

## Concurrency Model

The SDK uses **structured concurrency** (`async/await`) throughout, with Combine for reactive state publishing.

| Mechanism | Used For |
|-----------|---------|
| `async/await` | All I/O: API calls, S3 uploads, encoding, database reads/writes |
| `AsyncStream` | Bridging synchronous AVAudioEngine callbacks to the async pipeline |
| `Task` (detached) | Fire-and-forget chunk uploads in `ChunkUploadCoordinator` |
| `AsyncSemaphore` | Bounding concurrent S3 uploads to 10 |
| `CurrentValueSubject` | Session state (replays the current value to new subscribers) |
| `PassthroughSubject` | Voice activity and audio quality streams (no replay) |
| `ManagedAtomic<Int>` | Lock-free head/tail indices in `PreBuffer` |
| `@unchecked Sendable` | Components that are logically thread-safe but use internal mutation |

---

## Key Design Patterns

| Pattern | Where |
|---------|-------|
| Singleton | `EkaScribe.shared` — one SDK instance per process |
| Factory | `Pipeline.Factory` — creates `Pipeline` instances with injected dependencies |
| Protocol-oriented DI | Every component receives its dependencies as protocol types (e.g. `AudioRecorder`, `AudioEncoder`, `ChunkUploader`, `DataManager`) |
| State machine | `SessionState` with `canTransition(to:)` validation |
| Fire-and-forget with bounded concurrency | `ChunkUploadCoordinator` + `AsyncSemaphore` |
| Idempotent retry | `TransactionManager.checkAndProgress()` resumes from the last successful stage |

---

## Testing Approach

The test suite lives in `Tests/EkaScribeSDKTests/` and mirrors the `Sources/` module structure. Each module has at least one test file. Tests are pure unit tests — no network calls, no file system I/O where avoidable.

**Key patterns:**
- `MockHelpers.swift` provides shared mock factories for common dependencies.
- Protocol-based DI makes every component replaceable with a mock.
- `SmokeTests.swift` runs a handful of cross-cutting integration assertions.
- Audio quality tests use pre-generated PCM data rather than real microphone input.

To run all tests:
```bash
swift test
```
