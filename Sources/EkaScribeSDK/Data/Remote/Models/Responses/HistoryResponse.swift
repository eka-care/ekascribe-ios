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

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bId              = try? c.decodeIfPresent(String.self, forKey: .bId)
            createdAt        = try? c.decodeIfPresent(String.self, forKey: .createdAt)
            flavour          = try? c.decodeIfPresent(String.self, forKey: .flavour)
            mode             = try? c.decodeIfPresent(String.self, forKey: .mode)
            oid              = try? c.decodeIfPresent(String.self, forKey: .oid)
            processingStatus = try? c.decodeIfPresent(String.self, forKey: .processingStatus)
            txnId            = try? c.decodeIfPresent(String.self, forKey: .txnId)
            userStatus       = try? c.decodeIfPresent(String.self, forKey: .userStatus)
            uuid             = try? c.decodeIfPresent(String.self, forKey: .uuid)
            version          = try? c.decodeIfPresent(String.self, forKey: .version)
            patientDetails   = try? c.decodeIfPresent(HistoryPatientDTO.self, forKey: .patientDetails)
        }
    }

    struct HistoryPatientDTO: Decodable {
        let age: String?
        let biologicalSex: String?
        let name: String?
        let patientId: String?
        let visitId: String?

        enum CodingKeys: String, CodingKey {
            case age
            case name                                   // canonical (new)
            case nameFallback = "username"              // legacy fallback
            case biologicalSex = "gender"               // canonical (new)
            case biologicalSexFallback = "biologicalSex" // legacy fallback
            case patientId = "oid"
            case visitId = "visit_id"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)

            // age: accept String or Int
            if let s = try? c.decodeIfPresent(String.self, forKey: .age) {
                age = s
            } else if let i = try? c.decodeIfPresent(Int.self, forKey: .age) {
                age = String(i)
            } else {
                age = nil
            }

            // name: canonical "name" → fallback "username"
            name = (try? c.decodeIfPresent(String.self, forKey: .name))
                ?? (try? c.decodeIfPresent(String.self, forKey: .nameFallback))

            // biologicalSex: canonical "gender" → fallback "biologicalSex"
            biologicalSex = (try? c.decodeIfPresent(String.self, forKey: .biologicalSex))
                ?? (try? c.decodeIfPresent(String.self, forKey: .biologicalSexFallback))

            patientId = try? c.decodeIfPresent(String.self, forKey: .patientId)
            visitId   = try? c.decodeIfPresent(String.self, forKey: .visitId)
        }
    }
}
