import Foundation

struct GetConfigResponse: Decodable {
    let data: ConfigData?

    struct ConfigData: Decodable {
        let consultationModes: [ModeItem]?
        let supportedLanguages: [LanguageItem]?
        let supportedOutputFormats: [TemplateItemDTO]?
        let maxSelection: MaxSelectionConfig?
        let selectedPreferences: SelectedPreferencesDTO?
        let myTemplates: [TemplateItemDTO]?

        enum CodingKeys: String, CodingKey {
            case consultationModes = "consultation_modes"
            case supportedLanguages = "supported_languages"
            case supportedOutputFormats = "supported_output_formats"
            case maxSelection = "max_selection"
            case selectedPreferences = "selected_preferences"
            case myTemplates = "my_templates"
        }
    }

    struct MaxSelectionConfig: Decodable {
        let supportedLanguages: Int?
        let supportedOutputFormats: Int?
        let consultationModes: Int?

        enum CodingKeys: String, CodingKey {
            case supportedLanguages = "supported_languages"
            case supportedOutputFormats = "supported_output_formats"
            case consultationModes = "consultation_modes"
        }
    }

    struct ModeItem: Decodable {
        let id: String?
        let name: String?
        let desc: String?
    }

    struct LanguageItem: Decodable {
        let id: String?
        let name: String?
    }

    struct TemplateItemDTO: Decodable {
        let id: String?
        let name: String?
    }

    struct ModelItem: Decodable {
        let id: String?
        let name: String?
        let desc: String?
    }

    struct SelectedPreferencesDTO: Decodable {
        let consultationMode: String?
        let languages: [LanguageItem]?
        let outputFormats: [TemplateItemDTO]?
        let modelType: String?

        enum CodingKeys: String, CodingKey {
            case consultationMode = "consultation_mode"
            case languages
            case outputFormats = "output_formats"
            case modelType = "model_type"
        }
    }
}
