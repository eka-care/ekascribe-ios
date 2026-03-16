import Foundation

/// Determines which backend environment the SDK targets.
public enum EkaScribeEnvironment: Sendable {
    case production
    case staging
    case dev

    var baseURL: String {
        switch self {
            case .production: return "https://api.eka.care"
            case .staging:    return "https://api.staging.eka.care"
            case .dev:        return "https://api.dev.eka.care"
        }
    }

    var credentialsURL: String {
        switch self {
            case .production: return "https://cog.eka.care/credentials"
            case .staging:    return "https://cog.staging.eka.care/credentials"
            case .dev:        return "https://cog.dev.eka.care/credentials"
        }
    }

    var bucketName: String {
        switch self {
            case .production: return "m-prod-voice-record"
            case .staging:    return "m-staging-voice-record"
            case .dev:        return "m-dev-voice-record"
        }
    }

    var refreshTokenPath: String {
        switch self {
            case .production: return "/connect-auth/v1/account/refresh-token"
            case .staging:    return "/connect-auth/v1/account/refresh-token"
            case .dev:        return "/connect-auth/v1/account/refresh-token"  
        }
    }
}
