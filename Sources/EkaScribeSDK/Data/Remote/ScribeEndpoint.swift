import Alamofire
import Foundation

/// All Scribe API endpoints, defined declaratively.
enum ScribeEndpoint: RequestProvider {
    case initTransaction(sessionId: String, body: InitTransactionRequest)
    case stopTransaction(sessionId: String, body: StopTransactionRequest)
    case commitTransaction(sessionId: String, body: StopTransactionRequest)
    case getTransactionResult(sessionId: String)
    case convertTransactionResult(sessionId: String, templateId: String)
    case updateSession(sessionId: String, body: [UpdateSessionRequestItem])
    case getTemplates
    case updateTemplates(body: UpdateTemplatesRequest)
    case getUserConfig
    case updateUserConfig(body: UpdateUserConfigRequest)
    case getHistory(count: Int?)

    var path: String {
        switch self {
        case .initTransaction(let sessionId, _):
            return "/voice/api/v2/transaction/init/\(sessionId)"
        case .stopTransaction(let sessionId, _):
            return "/voice/api/v2/transaction/stop/\(sessionId)"
        case .commitTransaction(let sessionId, _):
            return "/voice/api/v2/transaction/commit/\(sessionId)"
        case .getTransactionResult(let sessionId):
            return "/voice/api/v3/status/\(sessionId)"
        case .convertTransactionResult(let sessionId, let templateId):
            return "/voice/api/v1/transaction/\(sessionId)/convert-to-template/\(templateId)"
        case .updateSession(let sessionId, _):
            return "/voice/api/v3/status/\(sessionId)"
        case .getTemplates:
            return "/voice/api/v1/template"
        case .updateTemplates, .getUserConfig, .updateUserConfig:
            return "/voice/api/v2/config"
        case .getHistory:
            return "/voice/api/v2/transaction/history"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .initTransaction, .stopTransaction, .commitTransaction, .convertTransactionResult:
            return .post
        case .getTransactionResult, .getTemplates, .getUserConfig, .getHistory:
            return .get
        case .updateSession:
            return .patch
        case .updateTemplates, .updateUserConfig:
            return .put
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .initTransaction(_, let body): return body
        case .stopTransaction(_, let body): return body
        case .commitTransaction(_, let body): return body
        case .updateSession(_, let body): return body
        case .updateTemplates(let body): return body
        case .updateUserConfig(let body): return body
        case .convertTransactionResult, .getTransactionResult,
             .getTemplates, .getUserConfig, .getHistory:
            return nil
        }
    }

    var queryItems: [String: String] {
        switch self {
        case .getHistory(let count):
            guard let count else { return [:] }
            return ["count": String(count)]
        default:
            return [:]
        }
    }
}
