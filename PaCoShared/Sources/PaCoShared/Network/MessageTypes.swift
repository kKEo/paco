import Foundation

/// One-byte tag placed at the start of each frame body so the receiver can
/// unambiguously distinguish a request/command from a reply (no decode-guessing).
public enum FrameType: UInt8, Sendable {
    case message = 1
    case response = 2
}

/// Wire format shared by both ends: `[UInt32 big-endian body length][FrameType byte][json]`.
public enum FrameCodec {
    public static let headerLength = 4
    /// Upper bound on a frame body; anything larger is treated as garbage.
    public static let maxBodyLength = 1_048_576

    public static func encode(type: FrameType, json: Data) -> Data {
        var body = Data([type.rawValue])
        body.append(json)
        var length = UInt32(body.count).bigEndian
        var framed = Data(bytes: &length, count: headerLength)
        framed.append(body)
        return framed
    }

    /// The body length announced by a 4-byte header; nil if malformed or out of bounds.
    public static func bodyLength(header: Data) -> Int? {
        guard header.count == headerLength else { return nil }
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        guard length > 0, length < maxBodyLength else { return nil }
        return Int(length)
    }

    /// Split a frame body into its type (nil if unknown) and JSON payload.
    public static func decodeBody(_ body: Data) -> (type: FrameType?, json: Data)? {
        guard let first = body.first else { return nil }
        return (FrameType(rawValue: first), Data(body.dropFirst()))
    }
}

public enum PaCoCommand: String, Codable, Sendable {
    /// Parent → child: full `PolicyTransfer` (schedules + app restrictions).
    case updatePolicy
    case requestExtension
    case approveExtension
    case denyExtension
    /// Child → parent: verify a parent PIN typed on the child Mac. The parent
    /// answers with a `PaCoResponse` carrying `PINVerifyResult`; the PIN hash never
    /// leaves the parent, so it cannot be brute-forced offline from the child.
    case verifyPIN
}

public struct PaCoMessage: Codable, Sendable {
    public var command: PaCoCommand
    public var payload: Data?
    public var timestamp: Date

    public init(command: PaCoCommand, payload: Data? = nil) {
        self.command = command
        self.payload = payload
        self.timestamp = Date()
    }

    public func encoded() throws -> Data {
        FrameCodec.encode(type: .message, json: try JSONEncoder().encode(self))
    }
}

public struct PaCoResponse: Codable, Sendable {
    public var success: Bool
    public var payload: Data?
    public var error: String?

    public init(success: Bool, payload: Data? = nil, error: String? = nil) {
        self.success = success
        self.payload = payload
        self.error = error
    }

    public func encoded() throws -> Data {
        FrameCodec.encode(type: .response, json: try JSONEncoder().encode(self))
    }
}

public struct ExtensionRequestPayload: Codable, Sendable {
    public var requestId: UUID
    public var childDeviceName: String
    public var profileId: UUID?
    public var requestedMinutes: Int
    public var reason: String

    public init(requestId: UUID, childDeviceName: String, profileId: UUID? = nil, requestedMinutes: Int, reason: String = "") {
        self.requestId = requestId
        self.childDeviceName = childDeviceName
        self.profileId = profileId
        self.requestedMinutes = requestedMinutes
        self.reason = reason
    }
}

public struct ExtensionResponsePayload: Codable, Sendable {
    public var requestId: UUID
    public var status: ExtensionStatus
    /// Minutes of internet granted (present on approval); the child turns this into
    /// a temporary override window.
    public var grantedMinutes: Int?

    public init(requestId: UUID, status: ExtensionStatus, grantedMinutes: Int? = nil) {
        self.requestId = requestId
        self.status = status
        self.grantedMinutes = grantedMinutes
    }
}

/// Child → parent payload of `.verifyPIN`. The PIN travels only inside the
/// TLS-PSK session; `nonce` lets the child match the reply.
public struct PINVerifyRequest: Codable, Sendable {
    public var nonce: UUID
    public var pin: String

    public init(nonce: UUID, pin: String) {
        self.nonce = nonce
        self.pin = pin
    }
}

/// Parent → child reply payload for `.verifyPIN`.
public struct PINVerifyResult: Codable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case success
        case incorrect
        case lockedOut
        case noPIN
    }

    public var nonce: UUID
    public var outcome: Outcome
    /// Present when `outcome == .lockedOut`.
    public var lockedOutUntil: Date?

    public init(nonce: UUID, outcome: Outcome, lockedOutUntil: Date? = nil) {
        self.nonce = nonce
        self.outcome = outcome
        self.lockedOutUntil = lockedOutUntil
    }
}
