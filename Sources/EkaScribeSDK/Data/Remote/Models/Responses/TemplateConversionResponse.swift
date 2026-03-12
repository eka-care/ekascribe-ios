import Foundation

struct TemplateConversionResponse: Decodable {
    let message: String?
    let status: String?
    let error: ErrorDetailsDTO?
}
