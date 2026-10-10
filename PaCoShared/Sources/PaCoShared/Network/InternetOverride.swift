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

/// A parent's manual on/off from the dashboard. Timed, so a manual "off" during
/// an allowed window (or "on" during a blocked one) expires and the schedule
/// takes over again instead of sticking until the next schedule edge days later.
public struct ManualInternetOverride: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var until: Date

    public init(enabled: Bool, until: Date) {
        self.enabled = enabled
        self.until = until
    }

    public func isActive(at date: Date = Date()) -> Bool { until > date }
}
