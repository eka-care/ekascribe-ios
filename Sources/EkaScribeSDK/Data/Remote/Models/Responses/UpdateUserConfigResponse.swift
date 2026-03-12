import Foundation

struct UpdateUserConfigResponse: Decodable {
    let message: String?
    let status: String?
    let error: ErrorDetailsDTO?
}
