import Foundation

struct UploadMetadata {
    let chunkId: String
    let sessionId: String
    let chunkIndex: Int
    let fileName: String
    let folderName: String
    let bid: String
    var mimeType: String = "audio/mp4"
}
