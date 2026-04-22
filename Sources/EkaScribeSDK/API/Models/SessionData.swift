import Foundation

public struct SessionData: Sendable {
    public let templateId: String
    public let documentId: String
    public let data: String

    public init(templateId: String, documentId: String, data: String) {
        self.templateId = templateId
        self.documentId = documentId
        self.data = data
    }
}
