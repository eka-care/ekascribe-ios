import Foundation

protocol ChunkUploader {
    func upload(file: URL, metadata: UploadMetadata) async -> UploadResult
    func clearCache() async
}
