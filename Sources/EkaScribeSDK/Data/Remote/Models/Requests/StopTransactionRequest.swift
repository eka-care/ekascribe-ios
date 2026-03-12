import Foundation

struct StopTransactionRequest: Encodable {
    let audioFiles: [String]
    let chunkInfo: [[String: ChunkDataDTO]]

    enum CodingKeys: String, CodingKey {
        case audioFiles = "audio_files"
        case chunkInfo = "chunk_info"
    }
}

struct ChunkDataDTO: Encodable {
    let startTime: Double
    let endTime: Double

    enum CodingKeys: String, CodingKey {
        case startTime = "st"
        case endTime = "et"
    }
}
