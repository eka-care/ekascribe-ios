import Foundation

struct UpdateUserConfigResponse: Decodable {
    let message: String?
    let status: String?
    let result: UpdateUserConfigResult?
    let error: ErrorDetailsDTO?
}

struct UpdateUserConfigResult: Decodable {
    let action: String?
    let bId: String?
    let userUuid: String?

    enum CodingKeys: String, CodingKey {
        case action
        case bId = "b_id"
        case userUuid = "user_uuid"
    }
}
