import Foundation

public struct OutputTemplate: Sendable, Codable {
    public let templateId: String
    public var templateType: String
    public var templateName: String?

    public init(templateId: String, templateType: String = "custom", templateName: String? = nil) {
        self.templateId = templateId
        self.templateType = templateType
        self.templateName = templateName
    }
}
