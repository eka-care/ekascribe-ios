import Foundation

public enum TransactionResult {
    case success(folderName: String = "", bid: String = "")
    case error(message: String)
}

enum TransactionPollResult {
    case success(result: ScribeResultResponse)
    case failed(error: String)
    case timeout
}
