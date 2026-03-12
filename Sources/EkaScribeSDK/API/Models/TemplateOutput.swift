import Foundation

public struct TemplateOutput: Sendable {
    public let name: String?
    public let title: String?
    public let sections: [SectionData]
    public let sessionId: String
    public var templateId: String?
    public var isEditable: Bool
    public let type: TemplateType
    public var rawOutput: String?

    public init(
        name: String?,
        title: String?,
        sections: [SectionData],
        sessionId: String,
        templateId: String? = nil,
        isEditable: Bool = false,
        type: TemplateType,
        rawOutput: String? = nil
    ) {
        self.name = name
        self.title = title
        self.sections = sections
        self.sessionId = sessionId
        self.templateId = templateId
        self.isEditable = isEditable
        self.type = type
        self.rawOutput = rawOutput
    }
}

public enum TemplateType: String, Codable, Sendable {
    case markdown
    case json
    case ekaEmr = "eka_emr"
}

public struct SectionData: Sendable {
    public var title: String?
    public var value: String?

    public init(title: String? = nil, value: String? = nil) {
        self.title = title
        self.value = value
    }
}
