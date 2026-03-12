import Foundation

public struct PatientDetail: Sendable, Codable {
    public var age: Int?
    public var biologicalSex: String?
    public var name: String?
    public var patientId: String?
    public var visitId: String?

    public init(
        age: Int? = nil,
        biologicalSex: String? = nil,
        name: String? = nil,
        patientId: String? = nil,
        visitId: String? = nil
    ) {
        self.age = age
        self.biologicalSex = biologicalSex
        self.name = name
        self.patientId = patientId
        self.visitId = visitId
    }
}
