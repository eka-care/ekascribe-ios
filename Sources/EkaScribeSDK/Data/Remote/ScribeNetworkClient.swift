import Alamofire
import Foundation

/// Central network client for all Scribe API calls.
/// Holds a configured Alamofire Session with auth interceptor and logging.
final class ScribeNetworkClient: @unchecked Sendable {
    private let session: Session
    private let baseURL: String
    private let logger: Logger

    init(
        baseURL: String,
        clientInfo: ScribeClientInfo,
        tokenStorage: any EkaScribeTokenStorage,
        refreshTokenPath: String,
        logger: Logger
    ) {
        let interceptor = AuthInterceptor(
            baseURL: baseURL,
            clientInfo: clientInfo,
            tokenStorage: tokenStorage,
            refreshTokenPath: refreshTokenPath,
            logger: logger
        )
        let eventMonitors: [EventMonitor] = [APILogger(logger: logger)]
        self.session = Session(interceptor: interceptor, eventMonitors: eventMonitors)
        self.baseURL = baseURL
        self.logger = logger
    }

    func execute<T: Decodable>(_ endpoint: RequestProvider) async -> NetworkResult<T> {
        let url = baseURL + endpoint.path

        var headers = HTTPHeaders()
        for (key, value) in endpoint.additionalHeaders {
            headers.add(name: key, value: value)
        }

        let dataRequest: DataRequest

        if let body = endpoint.body {
            dataRequest = session.request(
                url,
                method: endpoint.method,
                parameters: AnyEncodable(body),
                encoder: JSONParameterEncoder.default,
                headers: headers.isEmpty ? nil : headers
            )
        } else if !endpoint.queryItems.isEmpty {
            dataRequest = session.request(
                url,
                method: endpoint.method,
                parameters: endpoint.queryItems,
                encoder: URLEncodedFormParameterEncoder.default,
                headers: headers.isEmpty ? nil : headers
            )
        } else {
            dataRequest = session.request(
                url,
                method: endpoint.method,
                headers: headers.isEmpty ? nil : headers
            )
        }

        let response = await dataRequest.validate().serializingDecodable(T.self).response
        let statusCode = response.response?.statusCode ?? -1

        switch response.result {
        case .success(let decoded):
            return .success(decoded, statusCode: statusCode)

        case .failure(let afError):
            if afError.isSessionTaskError || afError.isExplicitlyCancelledError {
                return .networkError(afError)
            }
            if let data = response.data {
                let message = extractErrorMessage(data: data)
                    ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
                return .serverError(statusCode: statusCode, message: message)
            }
            return .unknownError(afError)
        }
    }

    /// Execute a GET request against a full URL (e.g. credentials on a different host).
    func execute<T: Decodable>(url: String) async -> NetworkResult<T> {
        let dataRequest = session.request(url, method: .get)

        let response = await dataRequest.validate().serializingDecodable(T.self).response
        let statusCode = response.response?.statusCode ?? -1

        switch response.result {
        case .success(let decoded):
            return .success(decoded, statusCode: statusCode)

        case .failure(let afError):
            if afError.isSessionTaskError || afError.isExplicitlyCancelledError {
                return .networkError(afError)
            }
            if let data = response.data {
                let message = extractErrorMessage(data: data)
                    ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
                return .serverError(statusCode: statusCode, message: message)
            }
            return .unknownError(afError)
        }
    }

    private func extractErrorMessage(data: Data) -> String? {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return payload["message"] as? String
        }
        return nil
    }
}
