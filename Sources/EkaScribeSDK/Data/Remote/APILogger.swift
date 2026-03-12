import Alamofire
import Foundation

/// A custom Alamofire EventMonitor that intercepts all requests and responses
/// for debugging, printing payloads natively through the SDK Logger.
final class APILogger: EventMonitor, @unchecked Sendable {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        let curl = buildCurl(urlRequest)
        logger.debug("API-REQ", "\n\(curl)\n---------------------")
    }

    func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
        guard let urlRequest = request.request else { return }
        let url = urlRequest.url?.absoluteString ?? "UNKNOWN_URL"
        let method = urlRequest.httpMethod ?? "UNKNOWN"
        let statusCode = response.response?.statusCode ?? 0
        let elapsedTime = response.metrics?.taskInterval.duration ?? 0.0

        var bodyStr = "EMPTY"
        if let data = response.data {
            if let json = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyStr = String(data: pretty, encoding: .utf8) {
                bodyStr = prettyStr
            } else {
                bodyStr = String(data: data, encoding: .utf8) ?? "BINARY_OR_UNPARSABLE"
            }
        }

        logger.debug("API-RES", """
        \(method) \(statusCode) \(url) [\(String(format: "%.3fs", elapsedTime))]
        Response Body:
        \(bodyStr)
        ---------------------
        """)
    }

    private func buildCurl(_ request: URLRequest) -> String {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""

        var parts = ["curl -X \(method)"]

        if let headers = request.allHTTPHeaderFields {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("-H '\(key): \(escaped)'")
            }
        }

        if let body = request.httpBody, !body.isEmpty {
            if let bodyStr = String(data: body, encoding: .utf8) {
                let escaped = bodyStr.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("-d '\(escaped)'")
            }
        }

        parts.append("'\(url)'")
        return parts.joined(separator: " \\\n  ")
    }
}
