import Foundation

struct AudioChunk {
    let chunkId: String
    let sessionId: String
    let index: Int
    let frames: [AudioFrame]
    let startTimeMs: Int64
    let endTimeMs: Int64
    let quality: AudioQuality?

    var durationMs: Int64 {
        endTimeMs - startTimeMs
    }
}
