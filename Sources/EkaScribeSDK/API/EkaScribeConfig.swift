import Foundation

public struct EkaScribeConfig {
    public let sampleRate: Int
    public let frameSize: Int
    public let preferredChunkDurationSec: Int
    public let desperationChunkDurationSec: Int
    public let maxChunkDurationSec: Int
    public let enableAnalyser: Bool
    public let overlapDurationSec: Double
    public let debugMode: Bool
    public let fullAudioOutput: Bool
    public let maxUploadRetries: Int
    public let pollMaxRetries: Int
    public let pollDelayMs: Int
    public let baseURL: String
    public let credentialsURL: String
    public let bucketName: String
    public let authTokenProvider: @Sendable () async -> String?
    public let tokenStorage: (any EkaScribeTokenStorage)?
    public let refreshTokenPath: String

    public init(
        baseURL: String,
        credentialsURL: String,
        bucketName: String,
        authTokenProvider: @escaping @Sendable () async -> String?,
        tokenStorage: (any EkaScribeTokenStorage)? = nil,
        refreshTokenPath: String = "/connect-auth/v1/account/refresh-token",
        sampleRate: Int = 16000,
        frameSize: Int = 512,
        preferredChunkDurationSec: Int = 10,
        desperationChunkDurationSec: Int = 20,
        maxChunkDurationSec: Int = 25,
        enableAnalyser: Bool = true,
        overlapDurationSec: Double = 0.5,
        debugMode: Bool = false,
        fullAudioOutput: Bool = false,
        maxUploadRetries: Int = 2,
        pollMaxRetries: Int = 3,
        pollDelayMs: Int = 2000
    ) {
        self.baseURL = baseURL
        self.credentialsURL = credentialsURL
        self.bucketName = bucketName
        self.authTokenProvider = authTokenProvider
        self.tokenStorage = tokenStorage
        self.refreshTokenPath = refreshTokenPath
        self.sampleRate = sampleRate
        self.frameSize = frameSize
        self.preferredChunkDurationSec = preferredChunkDurationSec
        self.desperationChunkDurationSec = desperationChunkDurationSec
        self.maxChunkDurationSec = maxChunkDurationSec
        self.enableAnalyser = enableAnalyser
        self.overlapDurationSec = overlapDurationSec
        self.debugMode = debugMode
        self.fullAudioOutput = fullAudioOutput
        self.maxUploadRetries = maxUploadRetries
        self.pollMaxRetries = pollMaxRetries
        self.pollDelayMs = pollDelayMs
    }

    public init(
        baseURL: String,
        credentialsURL: String,
        bucketName: String,
        tokenStorage: any EkaScribeTokenStorage,
        refreshTokenPath: String = "/connect-auth/v1/account/refresh-token",
        sampleRate: Int = 16000,
        frameSize: Int = 512,
        preferredChunkDurationSec: Int = 10,
        desperationChunkDurationSec: Int = 20,
        maxChunkDurationSec: Int = 25,
        enableAnalyser: Bool = true,
        overlapDurationSec: Double = 0.5,
        debugMode: Bool = false,
        fullAudioOutput: Bool = false,
        maxUploadRetries: Int = 2,
        pollMaxRetries: Int = 3,
        pollDelayMs: Int = 2000
    ) {
        self.init(
            baseURL: baseURL,
            credentialsURL: credentialsURL,
            bucketName: bucketName,
            authTokenProvider: { tokenStorage.getAccessToken() },
            tokenStorage: tokenStorage,
            refreshTokenPath: refreshTokenPath,
            sampleRate: sampleRate,
            frameSize: frameSize,
            preferredChunkDurationSec: preferredChunkDurationSec,
            desperationChunkDurationSec: desperationChunkDurationSec,
            maxChunkDurationSec: maxChunkDurationSec,
            enableAnalyser: enableAnalyser,
            overlapDurationSec: overlapDurationSec,
            debugMode: debugMode,
            fullAudioOutput: fullAudioOutput,
            maxUploadRetries: maxUploadRetries,
            pollMaxRetries: pollMaxRetries,
            pollDelayMs: pollDelayMs
        )
    }
}
