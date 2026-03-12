import Foundation

public struct TemplateItem: Sendable {
    public let isDefault: Bool
    public let desc: String?
    public let id: String
    public let isFavorite: Bool
    public let sectionIds: [String]
    public let title: String

    public init(isDefault: Bool, desc: String?, id: String, isFavorite: Bool, sectionIds: [String], title: String) {
        self.isDefault = isDefault
        self.desc = desc
        self.id = id
        self.isFavorite = isFavorite
        self.sectionIds = sectionIds
        self.title = title
    }
}
