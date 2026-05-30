import Foundation

public enum NotificationEventKind: String, Codable, Sendable {
    case appBlocked
    case internetDisabled
    case internetEnabled
    case extensionRequested
    case extensionApproved
    case extensionDenied
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
