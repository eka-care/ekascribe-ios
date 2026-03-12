import Foundation

struct AudioFrame: Sendable {
    let pcm: [Int16]
    let timestampMs: Int64
    let sampleRate: Int
    let frameIndex: Int64
}
