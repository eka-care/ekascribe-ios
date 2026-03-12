import Foundation

struct TemplatesResponse: Decodable {
    let data: DataDTO?

    struct DataDTO: Decodable {
        let templates: [TemplateDTO]?
    }

    struct TemplateDTO: Decodable {
        let isDefault: Bool?
        let desc: String?
        let id: String?
        let isFavorite: Bool?
        let sectionIds: [String]?
        let title: String?

        enum CodingKeys: String, CodingKey {
            case isDefault = "default"
            case desc
            case id
            case isFavorite = "is_favorite"
            case sectionIds = "section_ids"
            case title
        }
    }
}
