import Foundation
import SwiftData

public enum DeviceRole: String, Codable, Sendable {
    case parent
    case child
}

@Model
public final class DeviceConfig {
    @Attribute(.unique) public var id: UUID
    public var role: DeviceRole
    public var childProfileId: UUID?
    public var internetEnabled: Bool

    public init(role: DeviceRole, childProfileId: UUID? = nil) {
        self.id = UUID()
        self.role = role
        self.childProfileId = childProfileId
        self.internetEnabled = true
    }
}
