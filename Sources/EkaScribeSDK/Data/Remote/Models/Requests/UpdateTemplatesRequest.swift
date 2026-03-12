import Foundation

struct UpdateTemplatesRequest: Encodable {
    let data: TemplatesData?
    let requestType: String = "user"

    enum CodingKeys: String, CodingKey {
        case data
        case requestType = "request_type"
    }

    struct TemplatesData: Encodable {
        let myTemplates: [String]

        enum CodingKeys: String, CodingKey {
            case myTemplates = "my_templates"
        }
    }
}
