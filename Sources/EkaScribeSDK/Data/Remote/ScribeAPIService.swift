import Foundation

final class ScribeAPIService: ScribeAPIServiceProtocol {
    private let networkClient: ScribeNetworkClient

    init(networkClient: ScribeNetworkClient) {
        self.networkClient = networkClient
    }

    func initTransaction(_ sessionId: String, _ request: InitTransactionRequest) async -> NetworkResult<InitTransactionResponse> {
        await networkClient.execute(ScribeEndpoint.initTransaction(sessionId: sessionId, body: request))
    }

    func stopTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse> {
        await networkClient.execute(ScribeEndpoint.stopTransaction(sessionId: sessionId, body: request))
    }

    func commitTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse> {
        await networkClient.execute(ScribeEndpoint.commitTransaction(sessionId: sessionId, body: request))
    }

    func getTransactionResult(_ sessionId: String) async -> NetworkResult<ScribeResultResponse> {
        await networkClient.execute(ScribeEndpoint.getTransactionResult(sessionId: sessionId))
    }

    func convertTransactionResult(_ sessionId: String, templateId: String) async -> NetworkResult<TemplateConversionResponse> {
        await networkClient.execute(ScribeEndpoint.convertTransactionResult(sessionId: sessionId, templateId: templateId))
    }

    func updateSession(_ sessionId: String, _ request: [UpdateSessionRequestItem]) async -> NetworkResult<UpdateSessionResponse> {
        await networkClient.execute(ScribeEndpoint.updateSession(sessionId: sessionId, body: request))
    }

    func getTemplates() async -> NetworkResult<TemplatesResponse> {
        await networkClient.execute(ScribeEndpoint.getTemplates)
    }

    func updateTemplates(_ request: UpdateTemplatesRequest) async -> NetworkResult<UpdateTemplateResponse> {
        await networkClient.execute(ScribeEndpoint.updateTemplates(body: request))
    }

    func getUserConfig() async -> NetworkResult<GetConfigResponse> {
        await networkClient.execute(ScribeEndpoint.getUserConfig)
    }

    func updateUserConfig(_ request: UpdateUserConfigRequest) async -> NetworkResult<UpdateUserConfigResponse> {
        await networkClient.execute(ScribeEndpoint.updateUserConfig(body: request))
    }

    func getHistory(count: Int?) async -> NetworkResult<HistoryResponse> {
        await networkClient.execute(ScribeEndpoint.getHistory(count: count))
    }
}
