import Foundation
import SwiftData

public enum ExtensionStatus: String, Codable, Sendable {
    case pending
    case approved
    case denied
}

@Model
public final class TimeExtensionRequest {
    @Attribute(.unique) public var id: UUID
    public var profileId: UUID?
    public var childDeviceName: String
    public var requestedMinutes: Int
    public var reason: String
    public var statusRaw: String
    public var requestedAt: Date
    public var respondedAt: Date?

    public var status: ExtensionStatus {
        get { ExtensionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        profileId: UUID? = nil,
        childDeviceName: String,
        requestedMinutes: Int,
        reason: String = ""
    ) {
        self.id = id
        self.profileId = profileId
        self.childDeviceName = childDeviceName
        self.requestedMinutes = requestedMinutes
        self.reason = reason
        self.statusRaw = ExtensionStatus.pending.rawValue
        self.requestedAt = Date()
    }
}
