import Foundation

/// Agent-written activity log entry (`events.json`, last 100). Not consumed by
/// the app yet; kept as the hook for user-facing notifications.
public enum NotificationEventKind: String, Codable, Sendable {
    case appBlocked
    case internetDisabled
    case internetEnabled
}

public struct NotificationEvent: Codable, Sendable, Identifiable {
    public var id: UUID
    public var kind: NotificationEventKind
    public var timestamp: Date
    public var payload: [String: String]

    public init(kind: NotificationEventKind, payload: [String: String] = [:]) {
        self.id = UUID()
        self.kind = kind
        self.timestamp = Date()
        self.payload = payload
    }
}
