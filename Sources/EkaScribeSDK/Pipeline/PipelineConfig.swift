import Foundation

struct PipelineConfig {
    let frameChannelCapacity: Int
    let chunkChannelCapacity: Int
    let enableAnalyser: Bool
    let preBufferCapacity: Int

    init(
        frameChannelCapacity: Int = 640,
        chunkChannelCapacity: Int = 80,
        enableAnalyser: Bool = true,
        preBufferCapacity: Int = 2000
    ) {
        self.frameChannelCapacity = frameChannelCapacity
        self.chunkChannelCapacity = chunkChannelCapacity
        self.enableAnalyser = enableAnalyser
        self.preBufferCapacity = preBufferCapacity
    }
}
