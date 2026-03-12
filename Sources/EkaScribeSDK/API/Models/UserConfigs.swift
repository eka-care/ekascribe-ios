import Foundation

public struct UserConfigs: Sendable {
    public let consultationModes: ConsultationModeConfig
    public let supportedLanguages: SupportedLanguagesConfig
    public let outputTemplates: OutputTemplatesConfig
    public let selectedUserPreferences: SelectedUserPreferences
    public let modelConfigs: ModelConfigs

    public init(
        consultationModes: ConsultationModeConfig,
        supportedLanguages: SupportedLanguagesConfig,
        outputTemplates: OutputTemplatesConfig,
        selectedUserPreferences: SelectedUserPreferences,
        modelConfigs: ModelConfigs
    ) {
        self.consultationModes = consultationModes
        self.supportedLanguages = supportedLanguages
        self.outputTemplates = outputTemplates
        self.selectedUserPreferences = selectedUserPreferences
        self.modelConfigs = modelConfigs
    }
}

public struct ConsultationModeConfig: Sendable {
    public let modes: [ConsultationMode]
    public let maxSelection: Int

    public init(modes: [ConsultationMode], maxSelection: Int) {
        self.modes = modes
        self.maxSelection = maxSelection
    }
}

public struct SupportedLanguagesConfig: Sendable {
    public let languages: [SupportedLanguage]
    public let maxSelection: Int

    public init(languages: [SupportedLanguage], maxSelection: Int) {
        self.languages = languages
        self.maxSelection = maxSelection
    }
}

public struct OutputTemplatesConfig: Sendable {
    public let templates: [ConfigOutputTemplate]
    public let maxSelection: Int

    public init(templates: [ConfigOutputTemplate], maxSelection: Int) {
        self.templates = templates
        self.maxSelection = maxSelection
    }
}

public struct ModelConfigs: Sendable {
    public let modelTypes: [ModelType]
    public let maxSelection: Int

    public init(modelTypes: [ModelType], maxSelection: Int) {
        self.modelTypes = modelTypes
        self.maxSelection = maxSelection
    }
}

public struct SelectedUserPreferences: Sendable {
    public var consultationMode: ConsultationMode?
    public var languages: [SupportedLanguage]
    public var outputTemplates: [ConfigOutputTemplate]
    public var modelType: ModelType?

    public init(
        consultationMode: ConsultationMode? = nil,
        languages: [SupportedLanguage] = [],
        outputTemplates: [ConfigOutputTemplate] = [],
        modelType: ModelType? = nil
    ) {
        self.consultationMode = consultationMode
        self.languages = languages
        self.outputTemplates = outputTemplates
        self.modelType = modelType
    }
}

public struct ConsultationMode: Sendable {
    public let id: String
    public let name: String
    public let desc: String

    public init(id: String, name: String, desc: String) {
        self.id = id
        self.name = name
        self.desc = desc
    }
}

public struct SupportedLanguage: Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ConfigOutputTemplate: Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ModelType: Sendable {
    public let id: String
    public let name: String
    public let desc: String

    public init(id: String, name: String, desc: String) {
        self.id = id
        self.name = name
        self.desc = desc
    }
}
