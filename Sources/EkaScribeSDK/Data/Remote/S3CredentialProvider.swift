import Alamofire
import AWSCore
import AWSS3
import Foundation

actor S3CredentialProvider {
    private let session: Session
    private let credentialsURL: String
    private let authTokenProvider: @Sendable () async -> String?
    private let logger: Logger
    private var cachedCredentials: S3Credentials?
    private var activeTransferKey: String?

    struct S3Credentials: Sendable {
        let accessKey: String
        let secretKey: String
        let sessionToken: String
    }

    init(
        credentialsURL: String,
        authTokenProvider: @escaping @Sendable () async -> String?,
        tokenStorage: (any EkaScribeTokenStorage)?,
        refreshBaseURL: String,
        refreshTokenPath: String,
        logger: Logger
    ) {
        let interceptor = AuthInterceptor(
            baseURL: refreshBaseURL,
            tokenProvider: authTokenProvider,
            tokenStorage: tokenStorage,
            refreshTokenPath: refreshTokenPath,
            logger: logger
        )
        self.session = Session(interceptor: interceptor)
        self.credentialsURL = credentialsURL
        self.authTokenProvider = authTokenProvider
        self.logger = logger
    }

    func getCredentials() async -> S3Credentials? {
        if let cachedCredentials {
            return cachedCredentials
        }
        let fetched = await fetchCredentials()
        cachedCredentials = fetched
        if let fetched {
            configureTransferUtility(fetched)
        }
        return fetched
    }

    func refreshCredentials() async -> S3Credentials? {
        let fetched = await fetchCredentials()
        cachedCredentials = fetched
        if let fetched {
            configureTransferUtility(fetched)
        }
        return fetched
    }

    func getTransferUtilityKey() -> String? {
        guard let key = activeTransferKey else {
            logger.error("S3Credentials", "No active TransferUtility key set")
            return nil
        }
        return key
    }

    func removeTransferUtility(forKey key: String) {
        AWSS3TransferUtility.remove(forKey: key)
        if activeTransferKey == key {
            activeTransferKey = nil
        }
        logger.debug("S3Credentials", "Removed TransferUtility with key: \(key)")
    }

    private func configureTransferUtility(_ credentials: S3Credentials) {
        let sessionCredentials = AWSBasicSessionCredentialsProvider(
            accessKey: credentials.accessKey,
            secretKey: credentials.secretKey,
            sessionToken: credentials.sessionToken
        )

        guard let serviceConfig = AWSServiceConfiguration(
            region: .APSouth1,
            credentialsProvider: sessionCredentials
        ) else {
            logger.error("S3Credentials", "Failed to create AWSServiceConfiguration")
            return
        }

        let transferConfig = AWSS3TransferUtilityConfiguration()
        transferConfig.isAccelerateModeEnabled = false

        let newKey = "S3TransferUtility-\(UUID().uuidString)"
        AWSS3TransferUtility.register(
            with: serviceConfig,
            transferUtilityConfiguration: transferConfig,
            forKey: newKey
        )

        activeTransferKey = newKey
        logger.debug("S3Credentials", "Registered TransferUtility with key: \(newKey)")
    }

    private func fetchCredentials() async -> S3Credentials? {
        guard let url = URL(string: credentialsURL) else {
            logger.error("S3Credentials", "Invalid credentials URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = await authTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "auth")
        }

        do {
            let response = await session.request(request).serializingData().response
            let statusCode = response.response?.statusCode ?? -1

            switch response.result {
            case .success(let data):
                guard (200..<300).contains(statusCode) else {
                    logger.error("S3Credentials", "Credentials call failed with status: \(statusCode)")
                    return nil
                }

                let decoded = try JSONDecoder().decode(AwsS3ConfigResponse.self, from: data)
                guard
                    let access = decoded.credentials?.accessKeyId,
                    let secret = decoded.credentials?.secretKey,
                    let session = decoded.credentials?.sessionToken
                else {
                    logger.error("S3Credentials", "Missing credentials fields")
                    return nil
                }
                return S3Credentials(accessKey: access, secretKey: secret, sessionToken: session)

            case .failure(let afError):
                logger.error("S3Credentials", "Credential fetch failed", afError)
                return nil
            }
        } catch {
            logger.error("S3Credentials", "Credential fetch failed", error)
            return nil
        }
    }
}
