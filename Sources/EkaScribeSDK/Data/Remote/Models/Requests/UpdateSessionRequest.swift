import Foundation

struct UpdateSessionRequestItem: Encodable {
    let data: String
    let documentId: String

    enum CodingKeys: String, CodingKey {
        case data
        case documentId = "document-id"
    }
}
