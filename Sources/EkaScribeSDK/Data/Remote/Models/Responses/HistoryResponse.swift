import Foundation

struct HistoryResponse: Decodable {
    let data: [HistoryItemDTO]?

    struct HistoryItemDTO: Decodable {
        let bId: String?
        let createdAt: String?
        let flavour: String?
        let mode: String?
        let oid: String?
        let processingStatus: String?
        let txnId: String?
        let userStatus: String?
        let uuid: String?
        let version: String?
        let patientDetails: HistoryPatientDTO?

        enum CodingKeys: String, CodingKey {
            case bId = "b_id"
            case createdAt = "created_at"
            case flavour
            case mode
            case oid
            case processingStatus = "processing_status"
            case txnId = "txn_id"
            case userStatus = "user_status"
            case uuid
            case version
            case patientDetails = "patient_details"
        }
    }

    struct HistoryPatientDTO: Decodable {
        let age: Int?
        let biologicalSex: String?
        let name: String?
        let patientId: String?
        let visitId: String?

        enum CodingKeys: String, CodingKey {
            case age
            case biologicalSex
            case name = "username"
            case patientId = "oid"
            case visitId = "visit_id"
        }
    }
}
