import Alamofire
import Foundation

final class AuthInterceptor: RequestInterceptor, @unchecked Sendable {
    private let clientInfo: ScribeClientInfo
    private let tokenStorage: any EkaScribeTokenStorage
    private let refreshProvider: DefaultTokenProvider?

    init(
        baseURL: String,
        clientInfo: ScribeClientInfo,
        tokenStorage: any EkaScribeTokenStorage,
        refreshTokenPath: String,
        logger: Logger
    ) {
        self.clientInfo = clientInfo
        self.tokenStorage = tokenStorage
        if let refreshURL = URL(string: baseURL + refreshTokenPath) {
            self.refreshProvider = DefaultTokenProvider(
                tokenStorage: tokenStorage,
                refreshURL: refreshURL,
                clientInfo: clientInfo,
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
            request.setValue(clientInfo.clientId, forHTTPHeaderField: "client-id")
            request.setValue(clientInfo.flavour, forHTTPHeaderField: "flavour")
            if let token = tokenStorage.getAccessToken() {
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
            let refreshed = await refreshProvider.refreshTokens()
            if let refreshed, !refreshed.isEmpty {
                safeCompletion.closure(.retry)
            } else {
                await refreshProvider.sessionExpired()
                safeCompletion.closure(.doNotRetry)
            }
        }
    }
}

actor DefaultTokenProvider {
    private let tokenStorage: any EkaScribeTokenStorage
    private let refreshURL: URL
    private let clientInfo: ScribeClientInfo
    private let logger: Logger
    private let refreshSession: Session

    init(tokenStorage: any EkaScribeTokenStorage, refreshURL: URL, clientInfo: ScribeClientInfo, logger: Logger) {
        self.tokenStorage = tokenStorage
        self.refreshURL = refreshURL
        self.clientInfo = clientInfo
        self.logger = logger
        self.refreshSession = Session(eventMonitors: [APILogger(logger: logger)])
    }

    func refreshTokens() async -> String? {
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

        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(sessionToken)",
            "Client-Id": clientInfo.clientId,
            "flavour": clientInfo.flavour
        ]

        let response = await refreshSession.request(
            refreshURL,
            method: .post,
            parameters: payload,
            encoder: JSONParameterEncoder.default,
            headers: headers
        )
        .validate()
        .serializingDecodable(AuthRefreshResponse.self)
        .response

        let statusCode = response.response?.statusCode ?? -1

        switch response.result {
        case .success(let decoded):
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

        case .failure(let afError):
            logger.warn("AuthInterceptor", "Token refresh failed (status: \(statusCode))", afError)
            return nil
        }
    }

    func sessionExpired() {
        tokenStorage.onSessionExpired()
    }
}

struct SendableClosure<T>: @unchecked Sendable {
    let closure: T
    init(_ closure: T) { self.closure = closure }
}
