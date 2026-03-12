import Foundation

struct InitTransactionResponse: Decodable {
    let bId: String?
    let message: String?
    let status: String?
    let txnId: String?
    let error: ErrorDetailsDTO?

    enum CodingKeys: String, CodingKey {
        case bId = "b_id"
        case message
        case status
        case txnId = "txn_id"
        case error
    }
}

struct ErrorDetailsDTO: Decodable {
    let code: String?
    let displayMessage: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case code
        case displayMessage = "display_message"
        case message
    }
}
