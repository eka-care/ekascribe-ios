import Foundation

public struct AudioQualityMetrics: Sendable {
    public let stoi: Float
    public let pesq: Float
    public let siSDR: Float
    public let overallScore: Float

    public init(stoi: Float, pesq: Float, siSDR: Float, overallScore: Float) {
        self.stoi = stoi
        self.pesq = pesq
        self.siSDR = siSDR
        self.overallScore = overallScore
    }
}
