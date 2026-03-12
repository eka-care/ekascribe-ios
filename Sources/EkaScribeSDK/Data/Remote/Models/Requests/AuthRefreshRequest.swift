import Foundation

struct AuthRefreshRequest: Encodable {
    let refresh: String
    let sessionToken: String

    enum CodingKeys: String, CodingKey {
        case refresh = "refresh_token"
        case sessionToken = "access_token"
    }
}
