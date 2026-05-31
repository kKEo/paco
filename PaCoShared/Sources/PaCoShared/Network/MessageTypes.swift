import Foundation

public enum PaCoCommand: String, Codable, Sendable {
    case enableInternet
    case disableInternet
    case getStatus
    case updateSchedules
    case updateAppRestrictions
    case getUsageData
    case pair
    case ping
    case requestExtension
    case approveExtension
    case denyExtension
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
        let data = try JSONEncoder().encode(self)
        // Prefix with 4-byte length header for framing
        var length = UInt32(data.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(data)
        return framed
    }

    public static func decode(from data: Data) throws -> PaCoMessage {
        // Skip 4-byte length header
        let jsonData = data.dropFirst(4)
        return try JSONDecoder().decode(PaCoMessage.self, from: Data(jsonData))
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
        let data = try JSONEncoder().encode(self)
        var length = UInt32(data.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(data)
        return framed
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

    public init(requestId: UUID, status: ExtensionStatus) {
        self.requestId = requestId
        self.status = status
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
