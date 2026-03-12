import Foundation

struct AuthRefreshResponse: Decodable {
    let sessionToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case sessionToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
