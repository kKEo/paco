import Foundation
import SwiftData

@Model
public final class PairingInfo {
    @Attribute(.unique) public var id: UUID
    public var parentDeviceName: String
    public var childDeviceName: String
    public var pairedAt: Date

    public init(parentDeviceName: String, childDeviceName: String) {
        self.id = UUID()
        self.parentDeviceName = parentDeviceName
        self.childDeviceName = childDeviceName
        self.pairedAt = Date()
    }
}
