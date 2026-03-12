import Foundation

struct UpdateSessionRequestItem: Encodable {
    let data: String
    let templateId: String

    enum CodingKeys: String, CodingKey {
        case data
        case templateId = "template-id"
    }
}
