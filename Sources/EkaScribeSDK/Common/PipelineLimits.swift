import Foundation

enum PipelineLimits {
    /// Max concurrent chunk uploads (recording drain + post-stop retry).
    /// SDK-internal constant by design — not surfaced to the host app.
    static let maxConcurrentUploads: Int = 10
}
