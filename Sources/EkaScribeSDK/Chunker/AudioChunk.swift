import Foundation

struct AudioChunk {
    let chunkId: String
    let sessionId: String
    let index: Int
    let frames: [AudioFrame]
    let startTimeMs: Int
    let endTimeMs: Int
    let quality: AudioQuality?

    var durationMs: Int {
        endTimeMs - startTimeMs
    }
}
