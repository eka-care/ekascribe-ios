import Foundation

struct AwsS3ConfigResponse: Decodable {
    let credentials: S3CredentialsDTO?
    let expiry: Int?
    let identityId: String?
    let token: String?

    enum CodingKeys: String, CodingKey {
        case credentials
        case expiry
        case identityId = "identity_id"
        case token
    }

    struct S3CredentialsDTO: Decodable {
        let accessKeyId: String?
        let expiration: String?
        let secretKey: String?
        let sessionToken: String?

        enum CodingKeys: String, CodingKey {
            case accessKeyId = "AccessKeyId"
            case expiration
            case secretKey = "SecretKey"
            case sessionToken = "SessionToken"
        }
    }
}
