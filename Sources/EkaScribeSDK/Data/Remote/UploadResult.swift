import Foundation

enum UploadResult {
    case success(url: String)
    case failure(error: String, isRetryable: Bool)
}
