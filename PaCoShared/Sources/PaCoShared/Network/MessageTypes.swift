import Foundation

/// One-byte tag placed at the start of each frame body so the receiver can
/// unambiguously distinguish a request/command from a reply (no decode-guessing).
public enum FrameType: UInt8, Sendable {
    case message = 1
    case response = 2
}

/// Build a length-prefixed frame: [UInt32 big-endian body length][FrameType byte][json].
func makeFrame(type: FrameType, json: Data) -> Data {
    var body = Data([type.rawValue])
    body.append(json)
    var length = UInt32(body.count).bigEndian
    var framed = Data(bytes: &length, count: 4)
    framed.append(body)
    return framed
}

public enum PaCoCommand: String, Codable, Sendable {
    case enableInternet
    case disableInternet
    case getStatus
    /// Parent → child: full `PolicyTransfer` (schedules + app restrictions).
    case updatePolicy
    case getUsageData
    case pair
    case ping
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
        makeFrame(type: .message, json: try JSONEncoder().encode(self))
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
        makeFrame(type: .response, json: try JSONEncoder().encode(self))
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

public struct DeviceStatus: Codable, Sendable {
    public var deviceName: String
    public var internetEnabled: Bool
    public var currentApp: String?
    public var internetDurationToday: TimeInterval
    public var appUsage: [AppUsageEntry]

    public init(
        deviceName: String,
        internetEnabled: Bool,
        currentApp: String? = nil,
        internetDurationToday: TimeInterval = 0,
        appUsage: [AppUsageEntry] = []
    ) {
        self.deviceName = deviceName
        self.internetEnabled = internetEnabled
        self.currentApp = currentApp
        self.internetDurationToday = internetDurationToday
        self.appUsage = appUsage
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
