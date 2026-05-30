import Foundation

/// Codable device config representation for network transfer and agent-side storage.
/// The agent cannot use SwiftData @Model classes, so this lightweight struct
/// is used for JSON serialization over Bonjour and local file caching.
public struct DeviceConfigTransfer: Codable, Sendable {
    public var activeProfileId: UUID?

    public init(activeProfileId: UUID?) {
        self.activeProfileId = activeProfileId
    }
}
