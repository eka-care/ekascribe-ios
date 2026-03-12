import Foundation

struct UpdateUserConfigRequest: Encodable {
    let data: UserConfigData?
    let requestType: String = "user"

    enum CodingKeys: String, CodingKey {
        case data
        case requestType = "request_type"
    }

    struct UserConfigData: Encodable {
        let consultationMode: String?
        let inputLanguages: [InputLanguageDTO]?
        let modelType: String?
        let outputFormatTemplate: [OutputTemplateDTO]?

        enum CodingKeys: String, CodingKey {
            case consultationMode = "consultation_mode"
            case inputLanguages = "input_languages"
            case modelType = "model_type"
            case outputFormatTemplate = "output_format_template"
        }
    }

    struct InputLanguageDTO: Encodable {
        let id: String?
        let name: String?
    }

    struct OutputTemplateDTO: Encodable {
        let id: String?
        let name: String?
        let templateType: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case templateType = "template_type"
        }
    }
}
