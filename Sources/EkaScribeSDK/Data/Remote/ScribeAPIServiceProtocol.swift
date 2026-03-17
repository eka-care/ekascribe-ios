import Foundation

protocol ScribeAPIServiceProtocol {
    func initTransaction(_ sessionId: String, _ request: InitTransactionRequest) async -> NetworkResult<InitTransactionResponse>
    func stopTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse>
    func commitTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse>
    func getTransactionResult(_ sessionId: String) async -> NetworkResult<ScribeResultResponse>
    func convertTransactionResult(_ sessionId: String, templateId: String) async -> NetworkResult<TemplateConversionResponse>
    func updateSession(_ sessionId: String, _ request: [UpdateSessionRequestItem]) async -> NetworkResult<UpdateSessionResponse>
    func getTemplates() async -> NetworkResult<TemplatesResponse>
    func updateTemplates(_ request: UpdateTemplatesRequest) async -> NetworkResult<UpdateTemplateResponse>
    func getUserConfig() async -> NetworkResult<GetConfigResponse>
    func updateUserConfig(_ request: UpdateUserConfigRequest) async -> NetworkResult<UpdateUserConfigResponse>
    func getHistory(count: Int?) async -> NetworkResult<HistoryResponse>
}
