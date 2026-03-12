import Foundation

public struct SessionData: Sendable {
    public let templateId: String
    public let data: String

    public init(templateId: String, data: String) {
        self.templateId = templateId
        self.data = data
    }
}
