import Alamofire
import Foundation

/// Describes an HTTP request declaratively.
/// The network client uses this to build and execute the actual Alamofire DataRequest.
protocol RequestProvider {
    /// The URL path relative to the base URL (e.g., "/voice/api/v2/transaction/init/{id}")
    var path: String { get }

    /// The HTTP method for this request.
    var method: HTTPMethod { get }

    /// Optional JSON-encodable body. Return nil for GET requests.
    var body: (any Encodable)? { get }

    /// Optional URL query parameters.
    var queryItems: [String: String] { get }

    /// Additional headers specific to this endpoint (beyond the defaults).
    var additionalHeaders: [String: String] { get }
}

extension RequestProvider {
    var body: (any Encodable)? { nil }
    var queryItems: [String: String] { [:] }
    var additionalHeaders: [String: String] { [:] }
}
