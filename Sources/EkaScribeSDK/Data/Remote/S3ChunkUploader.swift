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
            // Get credentials (cached on first attempt, refreshed on retry)
            let creds = attempt == 0
                ? await credentialProvider.getCredentials()
                : await credentialProvider.refreshCredentials()

            guard let creds else {
                logger.warn("S3Uploader", "Failed to get credentials on attempt \(attempt)")
                continue
            }

            // Create a per-upload TransferUtility
            guard let (transferKey, transferUtility) = createTransferUtility(from: creds) else {
                logger.warn("S3Uploader", "Failed to create TransferUtility on attempt \(attempt)")
                continue
            }

            let expression = AWSS3TransferUtilityUploadExpression()
            expression.setValue(metadata.bid, forRequestHeader: "x-amz-meta-bid")
            expression.setValue(metadata.sessionId, forRequestHeader: "x-amz-meta-txnid")
            let bucketName = bucketName

            let result: UploadResult = await withCheckedContinuation { continuation in
                let hasResumed = SendableAtomicBool(false)

                transferUtility.uploadFile(
                    file,
                    bucket: bucketName,
                    key: key,
                    contentType: metadata.mimeType,
                    expression: expression,
                    completionHandler: { _, error in
                        guard hasResumed.compareAndSwap(expected: false, newValue: true) else { return }
                        guard let error else {
                            continuation.resume(returning: .success(url: "s3://\(bucketName)/\(key)"))
                            return
                        }
                        continuation.resume(returning: .failure(
                            error: "S3 upload failed: \(error.localizedDescription)",
                            isRetryable: true
                        ))
                    }
                ).continueWith { task in
                    guard let error = task.error,
                          hasResumed.compareAndSwap(expected: false, newValue: true) else { return nil }
                    continuation.resume(returning: .failure(
                        error: "S3 upload task failed: \(error.localizedDescription)",
                        isRetryable: true
                    ))
                    return nil
                }
            }

            // Always clean up this upload's TransferUtility
            removeTransferUtility(forKey: transferKey)

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

    // MARK: - Private

    private func createTransferUtility(
        from credentials: S3CredentialProvider.S3Credentials
    ) -> (key: String, utility: AWSS3TransferUtility)? {
        let sessionCredentials = AWSBasicSessionCredentialsProvider(
            accessKey: credentials.accessKey,
            secretKey: credentials.secretKey,
            sessionToken: credentials.sessionToken
        )

        guard let serviceConfig = AWSServiceConfiguration(
            region: .APSouth1,
            credentialsProvider: sessionCredentials
        ) else {
            logger.error("S3Uploader", "Failed to create AWSServiceConfiguration")
            return nil
        }

        let transferConfig = AWSS3TransferUtilityConfiguration()
        transferConfig.isAccelerateModeEnabled = false

        let key = "S3TransferUtility-\(UUID().uuidString)"
        AWSS3TransferUtility.register(
            with: serviceConfig,
            transferUtilityConfiguration: transferConfig,
            forKey: key
        )

        guard let utility = AWSS3TransferUtility.s3TransferUtility(forKey: key) else {
            logger.error("S3Uploader", "Failed to retrieve TransferUtility after registration for key: \(key)")
            AWSS3TransferUtility.remove(forKey: key)
            return nil
        }

        logger.debug("S3Uploader", "Created TransferUtility with key: \(key)")
        return (key, utility)
    }

    private func removeTransferUtility(forKey key: String) {
        AWSS3TransferUtility.remove(forKey: key)
        logger.debug("S3Uploader", "Removed TransferUtility with key: \(key)")
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
