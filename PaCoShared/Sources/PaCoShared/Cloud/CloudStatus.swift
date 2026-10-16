import Foundation

/// The daemon's PaCo Cloud state as shown by the child app (sent over XPC).
public struct CloudStatus: Codable, Sendable, Equatable {
    public var enrolled: Bool
    public var serverURL: URL?
    public var deviceId: UUID?
    public var deviceName: String?
    /// The server answered recently (a heartbeat or poll within `onlineWindow`).
    public var connected: Bool
    public var lastContactAt: Date?
    public var lastError: String?
    /// Time-extension requests sent through the cloud, newest last.
    public var requests: [ChildRequestRecord]

    /// Mirrors the server's online window for a device.
    public static let onlineWindow: TimeInterval = 90

    public static let notEnrolled = CloudStatus(
        enrolled: false, serverURL: nil, deviceId: nil, deviceName: nil,
        connected: false, lastContactAt: nil, lastError: nil, requests: [])

    public init(
        enrolled: Bool,
        serverURL: URL?,
        deviceId: UUID?,
        deviceName: String?,
        connected: Bool,
        lastContactAt: Date?,
        lastError: String?,
        requests: [ChildRequestRecord]
    ) {
        self.enrolled = enrolled
        self.serverURL = serverURL
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.connected = connected
        self.lastContactAt = lastContactAt
        self.lastError = lastError
        self.requests = requests
    }

    public var pendingRequest: ChildRequestRecord? { requests.last(where: \.isPending) }
    public var latestRequest: ChildRequestRecord? { requests.last }
}

/// The one cloud XPC call (`DaemonXPCProtocol.cloud`) carries one of these,
/// JSON-encoded with `CloudCodec`. Keeps the `@objc` surface to a single method.
public enum CloudXPCRequest: Codable, Sendable, Equatable {
    case enroll(serverURL: String, code: String, deviceName: String)
    case unenroll
    case status
    case submitExtensionRequest(requestId: UUID, requestedMinutes: Int, reason: String)
    case withdrawRequest(requestId: UUID)
    case verifyPIN(nonce: UUID, pin: String)
}

public struct CloudXPCResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    /// A sentence the app can show as is.
    public var error: String?
    public var status: CloudStatus?
    public var pinResult: PINVerifyResult?

    public init(ok: Bool, error: String? = nil, status: CloudStatus? = nil, pinResult: PINVerifyResult? = nil) {
        self.ok = ok
        self.error = error
        self.status = status
        self.pinResult = pinResult
    }

    public static func failure(_ message: String, status: CloudStatus? = nil) -> CloudXPCResponse {
        CloudXPCResponse(ok: false, error: message, status: status)
    }
}
