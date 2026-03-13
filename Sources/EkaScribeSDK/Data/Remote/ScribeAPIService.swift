import Alamofire
import Foundation

final class ScribeAPIService: ScribeAPIServiceProtocol {
    private let session: Session
    private let baseURL: String
    private let logger: Logger

    init(
        baseURL: String,
        authTokenProvider: @escaping @Sendable () async -> String?,
        tokenStorage: (any EkaScribeTokenStorage)?,
        refreshTokenPath: String,
        logger: Logger
    ) {
        let interceptor = AuthInterceptor(
            baseURL: baseURL,
            tokenProvider: authTokenProvider,
            tokenStorage: tokenStorage,
            refreshTokenPath: refreshTokenPath,
            logger: logger
        )
        let eventMonitors: [EventMonitor] = [APILogger(logger: logger)]
        self.session = Session(interceptor: interceptor, eventMonitors: eventMonitors)
        self.baseURL = baseURL
        self.logger = logger
    }

    func initTransaction(_ sessionId: String, _ request: InitTransactionRequest) async -> NetworkResult<InitTransactionResponse> {
        await perform(method: .post, path: "/voice/api/v2/transaction/init/\(sessionId)", body: request)
    }

    func stopTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse> {
        await perform(method: .post, path: "/voice/api/v2/transaction/stop/\(sessionId)", body: request)
    }

    func commitTransaction(_ sessionId: String, _ request: StopTransactionRequest) async -> NetworkResult<StopTransactionResponse> {
        await perform(method: .post, path: "/voice/api/v2/transaction/commit/\(sessionId)", body: request)
    }

    func getTransactionResult(_ sessionId: String) async -> NetworkResult<ScribeResultResponse> {
        await perform(method: .get, path: "/voice/api/v3/status/\(sessionId)")
    }

    func convertTransactionResult(_ sessionId: String, templateId: String) async -> NetworkResult<TemplateConversionResponse> {
        await perform(
            method: .post,
            path: "/voice/api/v1/transaction/\(sessionId)/convert-to-template/\(templateId)"
        )
    }

    func updateSession(_ sessionId: String, _ request: [UpdateSessionRequestItem]) async -> NetworkResult<UpdateSessionResponse> {
        await perform(method: .patch, path: "/voice/api/v3/status/\(sessionId)", body: request)
    }

    func getTemplates() async -> NetworkResult<TemplatesResponse> {
        await perform(method: .get, path: "/voice/api/v1/template")
    }

    func updateTemplates(_ request: UpdateTemplatesRequest) async -> NetworkResult<UpdateTemplateResponse> {
        await perform(method: .put, path: "/voice/api/v2/config", body: request)
    }

    func getUserConfig() async -> NetworkResult<GetConfigResponse> {
        await perform(method: .get, path: "/voice/api/v2/config")
    }

    func updateUserConfig(_ request: UpdateUserConfigRequest) async -> NetworkResult<UpdateUserConfigResponse> {
        await perform(method: .put, path: "/voice/api/v2/config", body: request)
    }

    func getHistory(count: Int?) async -> NetworkResult<HistoryResponse> {
        var query: [String: String] = [:]
        if let count {
            query["count"] = String(count)
        }
        return await perform(method: .get, path: "/voice/api/v2/transaction/history", query: query)
    }

    private func perform<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String] = [:]
    ) async -> NetworkResult<T> {
        await perform(method: method, path: path, body: Optional<EmptyBody>.none, query: query)
    }

    private func perform<T: Decodable, B: Encodable>(
        method: HTTPMethod,
        path: String,
        body: B?,
        query: [String: String] = [:]
    ) async -> NetworkResult<T> {
        guard let url = buildURL(path: path, query: query) else {
            return .serverError(statusCode: -1, message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                return .unknownError(error)
            }
        }

        do {
            let response = await session.request(request).validate().serializingData().response
            let statusCode = response.response?.statusCode ?? -1
            switch response.result {
            case .success(let data):
                if (200..<300).contains(statusCode) {
                    do {
                        let decoded = try JSONDecoder().decode(T.self, from: data)
                        return .success(decoded, statusCode: statusCode)
                    } catch {
                        logger.error("API", "Decoding failed: \(path)", error)
                        return .unknownError(error)
                    }
                }
                let message = extractErrorMessage(data: data) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
                return .serverError(statusCode: statusCode, message: message)

            case .failure(let afError):
                if afError.isSessionTaskError || afError.isExplicitlyCancelledError {
                    return .networkError(afError)
                }
                // After .validate(), non-2xx responses end up here (including after retry)
                if let data = response.data {
                    let message = extractErrorMessage(data: data) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
                    return .serverError(statusCode: statusCode, message: message)
                }
                return .unknownError(afError)
            }
        }
    }

    private func buildURL(path: String, query: [String: String]) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        let prefix = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let suffix = path.hasPrefix("/") ? path : "/" + path
        components.path = prefix + suffix
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }

    private func extractErrorMessage(data: Data) -> String? {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return payload["message"] as? String
        }
        return nil
    }
}

private struct EmptyBody: Encodable {}

final class AuthInterceptor: RequestInterceptor, @unchecked Sendable {
    private let tokenProvider: @Sendable () async -> String?
    private let refreshProvider: DefaultTokenProvider?

    init(
        baseURL: String,
        tokenProvider: @escaping @Sendable () async -> String?,
        tokenStorage: (any EkaScribeTokenStorage)?,
        refreshTokenPath: String,
        logger: Logger
    ) {
        if let tokenStorage {
            self.tokenProvider = { tokenStorage.getAccessToken() }
        } else {
            self.tokenProvider = tokenProvider
        }
        if
            let tokenStorage,
            let refreshURL = Self.buildURL(baseURL: baseURL, path: refreshTokenPath)
        {
            self.refreshProvider = DefaultTokenProvider(
                tokenStorage: tokenStorage,
                refreshURL: refreshURL,
                logger: logger
            )
        } else {
            self.refreshProvider = nil
        }
    }

    func adapt(
        _ urlRequest: URLRequest,
        for _: Session,
        completion: @escaping (Result<URLRequest, Error>) -> Void
    ) {
        let safeCompletion = SendableClosure(completion)
        Task {
            var request = urlRequest
            if let token = await tokenProvider() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue(token, forHTTPHeaderField: "auth")
            }
            safeCompletion.closure(.success(request))
        }
    }

    func retry(
        _ request: Request,
        for _: Session,
        dueTo _: Error,
        completion: @escaping (RetryResult) -> Void
    ) {
        let safeCompletion = SendableClosure(completion)
        guard request.response?.statusCode == 401 else {
            safeCompletion.closure(.doNotRetry)
            return
        }
        guard request.retryCount < 1 else {
            safeCompletion.closure(.doNotRetry)
            return
        }
        guard let refreshProvider else {
            safeCompletion.closure(.doNotRetry)
            return
        }

        Task {
            let refreshed = await refreshProvider.refreshTokenIfNeeded()
            if let refreshed, !refreshed.isEmpty {
                safeCompletion.closure(.retry)
            } else {
                await refreshProvider.sessionExpired()
                safeCompletion.closure(.doNotRetry)
            }
        }
    }

    private static func buildURL(baseURL: String, path: String) -> URL? {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        guard var components = URLComponents(string: baseURL) else { return nil }
        let prefix = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let suffix = path.hasPrefix("/") ? path : "/" + path
        components.path = prefix + suffix
        components.queryItems = nil
        return components.url
    }
}

private actor DefaultTokenProvider {
    private let tokenStorage: any EkaScribeTokenStorage
    private let refreshURL: URL
    private let logger: Logger
    private var refreshTask: Task<String?, Never>?

    init(tokenStorage: any EkaScribeTokenStorage, refreshURL: URL, logger: Logger) {
        self.tokenStorage = tokenStorage
        self.refreshURL = refreshURL
        self.logger = logger
    }

    func refreshTokenIfNeeded() async -> String? {
        if !shouldRefreshToken() {
            return tokenStorage.getAccessToken()
        }

        if let refreshTask {
            return await refreshTask.value
        }

        let task = Task { [weak self] in
            await self?.refreshTokens()
        }
        refreshTask = task
        let refreshed = await task.value
        refreshTask = nil
        return refreshed
    }

    func sessionExpired() {
        tokenStorage.onSessionExpired()
    }

    private func refreshTokens() async -> String? {
        guard
            let refreshToken = tokenStorage.getRefreshToken(),
            !refreshToken.isEmpty,
            let sessionToken = tokenStorage.getAccessToken(),
            !sessionToken.isEmpty
        else {
            logger.warn("AuthInterceptor", "Token refresh skipped: missing access/refresh token")
            return nil
        }

        let payload = AuthRefreshRequest(refresh: refreshToken, sessionToken: sessionToken)
        var request = URLRequest(url: refreshURL)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(statusCode) else {
                logger.warn("AuthInterceptor", "Token refresh failed with status: \(statusCode)")
                return nil
            }

            let decoded = try JSONDecoder().decode(AuthRefreshResponse.self, from: data)
            guard
                let newAccess = decoded.sessionToken,
                !newAccess.isEmpty,
                let newRefresh = decoded.refreshToken,
                !newRefresh.isEmpty
            else {
                logger.warn("AuthInterceptor", "Token refresh failed: invalid response body")
                return nil
            }

            tokenStorage.saveTokens(accessToken: newAccess, refreshToken: newRefresh)
            return newAccess
        } catch {
            logger.warn("AuthInterceptor", "Token refresh failed with exception", error)
            return nil
        }
    }

    /**
     Mirrors Android `DefaultTokenProvider.shouldRefreshToken()` behavior.
     */
    private func shouldRefreshToken() -> Bool {
        guard let token = tokenStorage.getAccessToken(), !token.isEmpty else {
            return true
        }

        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            return true
        }

        guard
            let payloadData = decodeBase64URL(String(parts[1])),
            let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let exp = payload["exp"] as? NSNumber
        else {
            return true
        }

        // JWT exp is in seconds (Unix timestamp), compare in same unit
        let currentTimeSec = Date().timeIntervalSince1970
        return currentTimeSec > exp.doubleValue
    }

    private func decodeBase64URL(_ encoded: String) -> Data? {
        var base64 = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }
}

private struct SendableClosure<T>: @unchecked Sendable {
    let closure: T
    init(_ closure: T) { self.closure = closure }
}
