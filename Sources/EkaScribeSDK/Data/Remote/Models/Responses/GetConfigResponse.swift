import Foundation

struct GetConfigResponse: Decodable {
    let data: ConfigData?

    struct ConfigData: Decodable {
        let consultationModes: SelectionConfig<ModeItem>?
        let supportedLanguages: SelectionConfig<LanguageItem>?
        let outputTemplates: SelectionConfig<TemplateItemDTO>?
        let selectedUserPreferences: SelectedPreferencesDTO?
        let modelConfigs: SelectionConfig<ModelItem>?

        enum CodingKeys: String, CodingKey {
            case consultationModes = "consultation_modes"
            case supportedLanguages = "supported_languages"
            case outputTemplates = "supported_output_formats"
            case selectedUserPreferences = "selected_preferences"
            case modelConfigs = "model_configs"
        }
    }

    struct SelectionConfig<T: Decodable>: Decodable {
        let items: [T]?
        let maxSelection: Int?

        enum CodingKeys: String, CodingKey {
            case items
            case maxSelection = "max_selection"
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
        let consultationMode: ModeItem?
        let languages: [LanguageItem]?
        let outputTemplates: [TemplateItemDTO]?
        let modelType: ModelItem?

        enum CodingKeys: String, CodingKey {
            case consultationMode = "consultation_mode"
            case languages
            case outputTemplates = "output_formats"
            case modelType = "model_type"
        }
    }
}
