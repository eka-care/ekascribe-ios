import Foundation

struct AudioQuality {
    let stoi: Float
    let pesq: Float
    let siSDR: Float
    let overallScore: Float
}

extension AudioQuality {
    func toMetrics() -> AudioQualityMetrics {
        AudioQualityMetrics(stoi: stoi, pesq: pesq, siSDR: siSDR, overallScore: overallScore)
    }
}
