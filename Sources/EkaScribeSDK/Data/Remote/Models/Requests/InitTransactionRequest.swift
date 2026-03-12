import Foundation

struct InitTransactionRequest: Encodable {
    let inputLanguage: [String]?
    let mode: String
    let outputFormatTemplate: [OutputFormatTemplateDTO]?
    let s3Url: String?
    let section: String?
    let speciality: String?
    let transfer: String = "vaded"
    let modelType: String
    let patientDetails: PatientDetailsDTO?

    enum CodingKeys: String, CodingKey {
        case inputLanguage = "input_language"
        case mode
        case section = "Section"
        case speciality
        case transfer
        case outputFormatTemplate = "output_format_template"
        case s3Url = "s3_url"
        case modelType = "model_type"
        case patientDetails = "patient_details"
    }
}

struct OutputFormatTemplateDTO: Encodable {
    let templateId: String?
    let type: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case templateId = "template_id"
        case name = "template_name"
        case type = "template_type"
    }
}

struct PatientDetailsDTO: Encodable {
    let age: Int?
    let biologicalSex: String?
    let name: String?
    let patientId: String?
    let visitId: String?

    enum CodingKeys: String, CodingKey {
        case age
        case biologicalSex
        case name = "username"
        case patientId = "oid"
        case visitId = "visit_id"
    }
}
