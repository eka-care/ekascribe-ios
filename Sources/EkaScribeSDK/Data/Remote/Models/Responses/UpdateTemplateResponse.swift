import Foundation

struct UpdateTemplateResponse: Decodable {
    let message: String?
    let status: String?
    let error: ErrorDetailsDTO?
}
