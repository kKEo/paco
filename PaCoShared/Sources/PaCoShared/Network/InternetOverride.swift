import Foundation

/// A temporary "allow internet until <expiry>" grant that supersedes schedule
/// blocking. Granted to the daemon (over XPC) when a parent approves a
/// time-extension request; the daemon keeps it inside its root-owned
/// `DaemonPolicy`, so the monitored user cannot forge or extend it.
public struct InternetOverride: Codable, Sendable, Equatable {
    public var requestId: UUID
    public var grantedUntil: Date

    public init(requestId: UUID, grantedUntil: Date) {
        self.requestId = requestId
        self.grantedUntil = grantedUntil
    }

    public func isActive(at date: Date = Date()) -> Bool { grantedUntil > date }
}
