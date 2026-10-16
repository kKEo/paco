import Foundation
import SwiftData

public enum DeviceRole: String, Codable, Sendable {
    case parent
    case child
}

/// Who manages a child Mac: a parent Mac on the same network (Bonjour) or
/// PaCo Cloud (a parent with only a browser). Exactly one at a time.
public enum DeviceController: String, Codable, Sendable {
    case localParent
    case cloud
}

@Model
public final class DeviceConfig {
    @Attribute(.unique) public var id: UUID
    public var role: DeviceRole
    public var childProfileId: UUID?
    /// `DeviceController` raw value; nil (stores created before PaCo Cloud) = local parent.
    public var controllerRaw: String?

    public init(role: DeviceRole, childProfileId: UUID? = nil, controller: DeviceController = .localParent) {
        self.id = UUID()
        self.role = role
        self.childProfileId = childProfileId
        self.controllerRaw = controller.rawValue
    }

    public var controller: DeviceController {
        get { controllerRaw.flatMap(DeviceController.init(rawValue:)) ?? .localParent }
        set { controllerRaw = newValue.rawValue }
    }
}
