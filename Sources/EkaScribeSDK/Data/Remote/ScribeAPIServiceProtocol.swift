import Foundation

protocol ScribeAPIServiceProtocol {
    func initTransaction(_ sessionId: String, _ request: InitTransactionRequest) async -> NetworkResult<InitTransactionResponse>
    func stopTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse>
    func commitTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse>
    func getTransactionResult(_ sessionId: String) async -> NetworkResult<ScribeResultResponse>
}
