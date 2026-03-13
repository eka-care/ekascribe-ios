import Foundation

protocol TransactionManaging {
    func initTransaction(sessionId: String, sessionConfig: SessionConfig, folderName: String) async -> TransactionResult
    func retryFailedUploads(sessionId: String) async -> Bool
    func stopTransaction(sessionId: String) async -> TransactionResult
    func commitTransaction(sessionId: String) async -> TransactionResult
    func pollResult(sessionId: String) async -> TransactionPollResult
}
