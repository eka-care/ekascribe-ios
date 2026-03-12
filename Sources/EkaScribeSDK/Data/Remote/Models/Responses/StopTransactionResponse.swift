import Foundation

struct StopTransactionResponse: Decodable {
    let message: String?
    let status: String?
    let error: ErrorDetailsDTO?
}
