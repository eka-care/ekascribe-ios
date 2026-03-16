import Foundation

/**
 Storage contract for session + refresh tokens.

 - provide current access/session token
 - provide current refresh token
 - persist refreshed token pair
 - notify when refresh is not possible and session is expired
 */
public protocol EkaScribeTokenStorage: AnyObject, Sendable {
    func getAccessToken() -> String?
    func getRefreshToken() -> String?
    func saveTokens(accessToken: String, refreshToken: String)
    func onSessionExpired()
}
