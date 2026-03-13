import Foundation

struct ScribeResultResponse: Decodable {
    let data: ResultData?

    struct ResultData: Decodable {
        let audioMatrix: AudioMatrixDTO?
        let createdAt: String?
        let output: [OutputDTO?]?
        let templateResults: TemplateResultsDTO?

        enum CodingKeys: String, CodingKey {
            case audioMatrix = "audio_matrix"
            case createdAt = "created_at"
            case output
            case templateResults = "template_results"
        }
    }

    struct AudioMatrixDTO: Decodable {
        let quality: Double?
    }

    struct OutputDTO: Decodable {
        let errors: [ResultErrorDTO?]?
        let name: String?
        let status: ResultStatus?
        let templateId: String?
        private let type: String?
        let value: String?
        let warnings: [ResultWarningDTO?]?
        
        var templateType: TemplateType? {
            TemplateType(rawValue: type ?? "")
        }

        enum CodingKeys: String, CodingKey {
            case errors
            case name
            case status
            case templateId = "template_id"
            case type
            case value
            case warnings
        }
    }

    struct TemplateResultsDTO: Decodable {
        let custom: [OutputDTO?]?
        let integration: [IntegrationDTO?]?
        let transcript: [TranscriptDTO?]?
    }

    struct TranscriptDTO: Decodable {
        let errors: [ResultErrorDTO?]?
        let lang: String?
        let status: ResultStatus?
        let type: String?
        let value: String?
        let warnings: [ResultWarningDTO?]?
    }

    struct IntegrationDTO: Decodable {
        let errors: [ResultErrorDTO?]?
        let name: String?
        let status: ResultStatus?
        let templateId: String?
        let type: String?
        let value: String?
        let warnings: [ResultWarningDTO?]?

        enum CodingKeys: String, CodingKey {
            case errors
            case name
            case status
            case templateId = "template_id"
            case type
            case value
            case warnings
        }
    }

    struct ResultErrorDTO: Decodable {
        let code: String?
        let msg: String?
        let type: String?
    }

    struct ResultWarningDTO: Decodable {
        let code: String?
        let msg: String?
        let type: String?
    }
}

enum ResultStatus: Decodable {
    case inProgress
    case success
    case failure
    case partialCompleted

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self).lowercased()
        switch raw {
        case "in-progress", "in_progress":
            self = .inProgress
        case "success":
            self = .success
        case "failure":
            self = .failure
        case "partial_success", "partial_completed":
            self = .partialCompleted
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown ResultStatus: \(raw)")
        }
    }
}
