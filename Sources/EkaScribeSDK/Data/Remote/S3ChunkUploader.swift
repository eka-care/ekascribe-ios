import AWSCore
import AWSS3
import Foundation
import Network

final class S3ChunkUploader: ChunkUploader, @unchecked Sendable {
    private let credentialProvider: S3CredentialProvider
    private let bucketName: String
    private let maxRetryCount: Int
    private let logger: Logger
    private let inFlightTracker = InFlightTracker()

    init(credentialProvider: S3CredentialProvider, bucketName: String, maxRetryCount: Int, logger: Logger) {
        self.credentialProvider = credentialProvider
        self.bucketName = bucketName
        self.maxRetryCount = maxRetryCount
        self.logger = logger
    }

    func upload(file: URL, metadata: UploadMetadata) async -> UploadResult {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return .failure(error: "Chunk file not found: \(file.path)", isRetryable: false)
        }

        guard await inFlightTracker.add(metadata.chunkId) else {
            return .failure(error: "Chunk upload already in progress", isRetryable: true)
        }

        defer {
            Task { await inFlightTracker.remove(metadata.chunkId) }
        }

        guard isNetworkAvailable() else {
            return .failure(error: "Network unavailable", isRetryable: true)
        }

        // Check file size without loading into memory
        let fileSize: UInt64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            fileSize = attrs[.size] as? UInt64 ?? 0
        } catch {
            return .failure(error: "Failed to read file attributes: \(error.localizedDescription)", isRetryable: false)
        }

        guard fileSize > 0 else {
            logger.warn("S3Uploader", "Empty file payload for chunk \(metadata.chunkId)")
            return .failure(error: "Empty file payload", isRetryable: false)
        }

        let key = "\(metadata.folderName)/\(metadata.sessionId)/\(metadata.fileName)"

        for attempt in 0...maxRetryCount {
            // Fetch credentials (refresh on retry); this also configures TransferUtility
            let creds = attempt == 0
                ? await credentialProvider.getCredentials()
                : await credentialProvider.refreshCredentials()

            guard creds != nil else {
                logger.warn("S3Uploader", "Failed to get credentials on attempt \(attempt)")
                continue
            }

            var transferKey = await credentialProvider.getTransferUtilityKey()
            var transferUtility = transferKey.flatMap { AWSS3TransferUtility.s3TransferUtility(forKey: $0) }

            // If TransferUtility is nil despite having credentials, force-refresh to
            // reconfigure it rather than wasting a retry attempt with `continue`.
            if transferUtility == nil {
                logger.warn("S3Uploader", "TransferUtility not available on attempt \(attempt), force-refreshing credentials")
                let refreshed = await credentialProvider.refreshCredentials()
                guard refreshed != nil else {
                    logger.warn("S3Uploader", "Force-refresh credentials failed on attempt \(attempt)")
                    continue
                }
                transferKey = await credentialProvider.getTransferUtilityKey()
                transferUtility = transferKey.flatMap { AWSS3TransferUtility.s3TransferUtility(forKey: $0) }
            }

            guard let transferKey, let transferUtility else {
                logger.warn("S3Uploader", "TransferUtility still not available after force-refresh on attempt \(attempt)")
                continue
            }

            let expression = AWSS3TransferUtilityUploadExpression()
            expression.setValue(metadata.bid, forRequestHeader: "x-amz-meta-bid")
            expression.setValue(metadata.sessionId, forRequestHeader: "x-amz-meta-txnid")

            let result: UploadResult = await withCheckedContinuation { continuation in
                // Ensure continuation is only resumed once
                let hasResumed = SendableAtomicBool(false)
                
                transferUtility.uploadFile(
                    file,
                    bucket: self.bucketName,
                    key: key,
                    contentType: metadata.mimeType,
                    expression: expression,
                    completionHandler: { _, error in
                        if hasResumed.compareAndSwap(expected: false, newValue: true) {
                            if let error = error {
                                continuation.resume(returning: .failure(
                                    error: "S3 upload failed: \(error.localizedDescription)",
                                    isRetryable: true
                                ))
                            } else {
                                let url = "s3://\(self.bucketName)/\(key)"
                                continuation.resume(returning: .success(url: url))
                            }
                        }
                    }
                ).continueWith { task in
                    if let error = task.error, hasResumed.compareAndSwap(expected: false, newValue: true) {
                        continuation.resume(returning: .failure(
                            error: "S3 upload task failed: \(error.localizedDescription)",
                            isRetryable: true
                        ))
                    }
                    return nil
                }
            }

            // Clean up TransferUtility for this upload
            await credentialProvider.removeTransferUtility(forKey: transferKey)

            switch result {
            case .success:
                logger.info("S3Uploader", "Uploaded chunk \(metadata.chunkId) to s3://\(bucketName)/\(key)")
                return result
            case .failure(let error, _):
                logger.warn("S3Uploader", "Upload attempt \(attempt) failed: \(error)")
                if attempt < maxRetryCount {
                    continue
                }
                return result
            }
        }

        return .failure(error: "Upload failed after \(maxRetryCount + 1) attempts", isRetryable: true)
    }

    func clearCache() async {
        await inFlightTracker.clear()
    }

    private func isNetworkAvailable() -> Bool {
        // Semaphores + NWPathMonitor often deadlock in Swift concurrency. 
        // For synchronous checks, it is safer to return true and let the URLSession fail natively, 
        // or keep an active monitor at the class level. Here, we assume true to prevent blocking.
        return true
    }
}

final class SendableAtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    func compareAndSwap(expected: Bool, newValue: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if value == expected {
            value = newValue
            return true
        }
        return false
    }
}

actor InFlightTracker {
    private var ids: Set<String> = []

    func add(_ id: String) -> Bool {
        ids.insert(id).inserted
    }

    func remove(_ id: String) {
        ids.remove(id)
    }

    func clear() {
        ids.removeAll()
    }
}
