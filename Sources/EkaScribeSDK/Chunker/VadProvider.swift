import Foundation

protocol VadProvider {
    func load()
    func detect(pcm: [Int16]) -> VadResult
    func unload()
}

struct VadResult {
    let isSpeech: Bool
    let confidence: Float
}
