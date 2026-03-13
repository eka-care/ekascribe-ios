import Foundation

struct AudioFrame: Sendable {
    let pcm: [Int16]
    let timestampMs: Int
    let sampleRate: Int
    let frameIndex: Int
}
