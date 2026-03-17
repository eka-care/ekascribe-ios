import Foundation

public struct EkaScribeConfig {
    public let environment: EkaScribeEnvironment
    public let sampleRate: SampleRate
    public let frameSize: FrameSize
    public let enableAnalyser: Bool
    public let debugMode: Bool
    public let fullAudioOutput: Bool
    public let clientInfo: ScribeClientInfo
    public let tokenStorage: any EkaScribeTokenStorage

    var baseURL: String { environment.baseURL }
    var credentialsURL: String { environment.credentialsURL }
    var bucketName: String { environment.bucketName }
    var refreshTokenPath: String { environment.refreshTokenPath }

    let preferredChunkDurationSec: Int = 10
    let desperationChunkDurationSec: Int = 20
    let maxChunkDurationSec: Int = 25
    let overlapDurationSec: Double = 0.5
    let maxUploadRetries: Int = 2
    let pollMaxRetries: Int = 3
    let pollDelayMs: Int = 2000

    public init(
        environment: EkaScribeEnvironment = .production,
        clientInfo: ScribeClientInfo,
        tokenStorage: any EkaScribeTokenStorage,
        sampleRate: SampleRate = .hz16000,
        frameSize: FrameSize = .samples512,
        enableAnalyser: Bool = true,
        debugMode: Bool = false,
        fullAudioOutput: Bool = false
    ) {
        self.environment = environment
        self.clientInfo = clientInfo
        self.tokenStorage = tokenStorage
        self.sampleRate = sampleRate
        self.frameSize = frameSize
        self.enableAnalyser = enableAnalyser
        self.debugMode = debugMode
        self.fullAudioOutput = fullAudioOutput
    }
}
