import Foundation

struct UpdateSessionResponse: Decodable {
    let message: String?
    let status: String?
    let error: ErrorDetailsDTO?
}
