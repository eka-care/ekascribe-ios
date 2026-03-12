import Foundation

public struct SessionResult: Sendable {
    public let templates: [TemplateOutput]
    public var audioQuality: Double?

    public init(templates: [TemplateOutput], audioQuality: Double? = nil) {
        self.templates = templates
        self.audioQuality = audioQuality
    }
}
