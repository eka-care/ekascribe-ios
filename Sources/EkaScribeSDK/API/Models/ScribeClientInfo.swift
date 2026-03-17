import Foundation

public struct ScribeClientInfo: Sendable {
    public let clientId: String
    public let flavour: String

    public init(clientId: String, flavour: String = "ScribeIOS") {
        self.clientId = clientId
        self.flavour = flavour
    }
}
