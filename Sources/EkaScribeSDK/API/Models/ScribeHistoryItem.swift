import Foundation

public struct ScribeHistoryItem: Sendable {
    public let bId: String?
    public let createdAt: String?
    public let flavour: String?
    public let mode: String?
    public let oid: String?
    public let processingStatus: String?
    public let txnId: String?
    public let userStatus: String?
    public let uuid: String?
    public let version: String?
    public let patientDetails: ScribePatientInfo?

    public init(
        bId: String? = nil,
        createdAt: String? = nil,
        flavour: String? = nil,
        mode: String? = nil,
        oid: String? = nil,
        processingStatus: String? = nil,
        txnId: String? = nil,
        userStatus: String? = nil,
        uuid: String? = nil,
        version: String? = nil,
        patientDetails: ScribePatientInfo? = nil
    ) {
        self.bId = bId
        self.createdAt = createdAt
        self.flavour = flavour
        self.mode = mode
        self.oid = oid
        self.processingStatus = processingStatus
        self.txnId = txnId
        self.userStatus = userStatus
        self.uuid = uuid
        self.version = version
        self.patientDetails = patientDetails
    }
}

public struct ScribePatientInfo: Sendable {
    public let age: Int?
    public let biologicalSex: String?
    public let name: String?
    public let patientId: String?
    public let visitId: String?

    public init(age: Int? = nil, biologicalSex: String? = nil, name: String? = nil, patientId: String? = nil, visitId: String? = nil) {
        self.age = age
        self.biologicalSex = biologicalSex
        self.name = name
        self.patientId = patientId
        self.visitId = visitId
    }
}
