import Foundation

/// A command from the parent, delivered by the events long-poll. Delivery is
/// at least once, so every time window carries an absolute end (`until`).
public struct CloudEvent: Decodable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case policyChanged(version: Int)
        case activeProfileChanged(profileId: UUID?)
        case approveExtension(requestId: UUID, grantedMinutes: Int, grantedUntil: Date)
        case denyExtension(requestId: UUID)
        case setManualInternet(enabled: Bool, minutes: Int, until: Date)
        case clearManualInternet
        case unenrolled
        /// A type this daemon version does not know; skipped (and acknowledged).
        case unknown(type: String)
    }

    public var id: Int
    public var kind: Kind
    public var createdAt: Date?

    public init(id: Int, kind: Kind, createdAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, type, payload, createdAt }

    private enum PayloadKeys: String, CodingKey {
        case version, profileId, requestId, grantedMinutes, grantedUntil, enabled, minutes, until
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        let type = try c.decode(String.self, forKey: .type)
        let p = try c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)

        switch type {
        case "policyChanged":
            kind = .policyChanged(version: try p.decode(Int.self, forKey: .version))
        case "activeProfileChanged":
            kind = .activeProfileChanged(profileId: try p.decodeIfPresent(UUID.self, forKey: .profileId))
        case "approveExtension":
            kind = .approveExtension(
                requestId: try p.decode(UUID.self, forKey: .requestId),
                grantedMinutes: try p.decode(Int.self, forKey: .grantedMinutes),
                grantedUntil: try p.decode(Date.self, forKey: .grantedUntil))
        case "denyExtension":
            kind = .denyExtension(requestId: try p.decode(UUID.self, forKey: .requestId))
        case "setManualInternet":
            kind = .setManualInternet(
                enabled: try p.decode(Bool.self, forKey: .enabled),
                minutes: try p.decode(Int.self, forKey: .minutes),
                until: try p.decode(Date.self, forKey: .until))
        case "clearManualInternet":
            kind = .clearManualInternet
        case "unenrolled":
            kind = .unenrolled
        default:
            kind = .unknown(type: type)
        }
    }
}
