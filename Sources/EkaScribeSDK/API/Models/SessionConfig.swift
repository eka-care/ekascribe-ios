import Foundation

public struct SessionConfig: Sendable {
    public var languages: [String]
    public var mode: String
    public var modelType: String
    public var outputTemplates: [OutputTemplate]?
    public var patientDetails: PatientDetail?
    public var section: String?
    public var speciality: String?

    public init(
        languages: [String],
        mode: String,
        modelType: String,
        outputTemplates: [OutputTemplate]? = nil,
        patientDetails: PatientDetail? = nil,
        section: String? = nil,
        speciality: String? = nil
    ) {
        self.languages = languages
        self.mode = mode
        self.modelType = modelType
        self.outputTemplates = outputTemplates
        self.patientDetails = patientDetails
        self.section = section
        self.speciality = speciality
    }
}
