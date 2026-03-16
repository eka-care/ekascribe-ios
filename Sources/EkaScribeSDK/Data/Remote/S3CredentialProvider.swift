import Alamofire
import Foundation

actor S3CredentialProvider {
    private let session: Session
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
        tokenStorage: any EkaScribeTokenStorage,
        refreshBaseURL: String,
        refreshTokenPath: String,
        logger: Logger
    ) {
        let interceptor = AuthInterceptor(
            baseURL: refreshBaseURL,
            tokenStorage: tokenStorage,
            refreshTokenPath: refreshTokenPath,
            logger: logger
        )
        self.session = Session(interceptor: interceptor)
        self.credentialsURL = credentialsURL
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
        let response = await session.request(credentialsURL, method: .get)
            .validate()
            .serializingDecodable(AwsS3ConfigResponse.self)
            .response

        switch response.result {
        case .success(let decoded):
            guard
                let access = decoded.credentials?.accessKeyId,
                let secret = decoded.credentials?.secretKey,
                let sessionToken = decoded.credentials?.sessionToken
            else {
                logger.error("S3Credentials", "Missing credentials fields")
                return nil
            }
            return S3Credentials(accessKey: access, secretKey: secret, sessionToken: sessionToken)

        case .failure(let afError):
            let statusCode = response.response?.statusCode ?? -1
            logger.error("S3Credentials", "Credential fetch failed (status: \(statusCode))", afError)
            return nil
        }
    }
}
