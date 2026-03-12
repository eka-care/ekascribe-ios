import Foundation

protocol AudioEncoder {
    func encode(frames: [AudioFrame], sampleRate: Int, outputPath: String) async throws -> EncodedChunk
    func encodeFromFile(pcmFilePath: String, sampleRate: Int, outputPath: String) async throws -> EncodedChunk
}
