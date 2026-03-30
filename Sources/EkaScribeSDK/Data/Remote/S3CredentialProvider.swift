import Foundation

actor S3CredentialProvider {
    private let networkClient: ScribeNetworkClient
    private let credentialsURL: String
    private let logger: Logger
    private var cachedCredentials: S3Credentials?

    struct S3Credentials: Sendable {
        let accessKey: String
        let secretKey: String
        let sessionToken: String
    }

    init(
        credentialsURL: String,
        networkClient: ScribeNetworkClient,
        logger: Logger
    ) {
        self.credentialsURL = credentialsURL
        self.networkClient = networkClient
        self.logger = logger
    }

    func getCredentials() async -> S3Credentials? {
        if let cachedCredentials {
            return cachedCredentials
        }
        return await refreshCredentials()
    }

    func refreshCredentials() async -> S3Credentials? {
        let fetched = await fetchCredentials()
        cachedCredentials = fetched
        return fetched
    }

    private func fetchCredentials() async -> S3Credentials? {
        let result: NetworkResult<AwsS3ConfigResponse> = await networkClient.execute(url: credentialsURL)

        switch result {
        case .success(let decoded, _):
            guard
                let access = decoded.credentials?.accessKeyId,
                let secret = decoded.credentials?.secretKey,
                let sessionToken = decoded.credentials?.sessionToken
            else {
                logger.error("S3Credentials", "Missing credentials fields")
                return nil
            }
            return S3Credentials(accessKey: access, secretKey: secret, sessionToken: sessionToken)

        case .serverError(let statusCode, let message, _):
            logger.error("S3Credentials", "Credential fetch failed (status: \(statusCode)): \(message)")
            return nil

        case .networkError(let error):
            logger.error("S3Credentials", "Credential fetch network error", error)
            return nil

        case .unknownError(let error):
            logger.error("S3Credentials", "Credential fetch unknown error", error)
            return nil
        }
    }
}
