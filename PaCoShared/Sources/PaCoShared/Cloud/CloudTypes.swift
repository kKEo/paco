import Foundation

// Request and response bodies of the PaCo Cloud device API (`/api/v1`).
// The server mirrors these shapes; `server/tests/Fixtures/policy.json` pins the
// policy part from both sides (see CloudFixtureTests).

/// `POST /api/v1/enroll`
public struct CloudEnrollRequest: Codable, Sendable, Equatable {
    public var code: String
    public var deviceName: String
    public var daemonVersion: String
    public var timeZone: String

    public init(code: String, deviceName: String, daemonVersion: String, timeZone: String) {
        self.code = code
        self.deviceName = deviceName
        self.daemonVersion = daemonVersion
        self.timeZone = timeZone
    }
}

public struct CloudEnrollResponse: Codable, Sendable, Equatable {
    public var deviceId: UUID
    public var deviceName: String
    public var deviceToken: String
    public var policyVersion: Int
    public var eventCursor: Int
    public var serverTime: Date
}

/// `GET /api/v1/device/policy`. `policy` is applied with `updatePolicy`,
/// `activeProfileId` with `setActiveProfile`. `manualOverride` is informational:
/// the toggle itself arrives as an event.
public struct CloudPolicyEnvelope: Codable, Sendable, Equatable {
    public var version: Int
    public var activeProfileId: UUID?
    public var manualOverride: ManualInternetOverride?
    public var policy: PolicyTransfer

    public init(version: Int, activeProfileId: UUID?, manualOverride: ManualInternetOverride?, policy: PolicyTransfer) {
        self.version = version
        self.activeProfileId = activeProfileId
        self.manualOverride = manualOverride
        self.policy = policy
    }
}

/// What the device is enforcing right now, sent with every heartbeat.
public struct CloudDeviceStatus: Codable, Sendable, Equatable {
    public var internetEnabled: Bool
    /// `allowed`, `blocked` or `gracePeriod`.
    public var action: String
    public var graceRemainingSeconds: Int?
    public var activeProfileId: UUID?
    public var manualOverride: ManualInternetOverride?
    public var override: InternetOverride?

    public init(policy: DaemonPolicy, internetEnabled: Bool, at date: Date = Date()) {
        self.internetEnabled = internetEnabled
        switch policy.internetAction(at: date) {
        case .allowed:
            action = "allowed"
        case .blocked:
            action = "blocked"
        case .gracePeriod(let remaining):
            action = "gracePeriod"
            graceRemainingSeconds = remaining
        }
        activeProfileId = policy.activeProfileId
        manualOverride = policy.activeManualOverride(at: date)
        override = policy.override.flatMap { $0.isActive(at: date) ? $0 : nil }
    }
}

/// `POST /api/v1/device/heartbeat`
public struct CloudHeartbeatRequest: Codable, Sendable, Equatable {
    public var policyVersion: Int
    public var daemonVersion: String
    public var timeZone: String
    public var status: CloudDeviceStatus

    public init(policyVersion: Int, daemonVersion: String, timeZone: String, status: CloudDeviceStatus) {
        self.policyVersion = policyVersion
        self.daemonVersion = daemonVersion
        self.timeZone = timeZone
        self.status = status
    }
}

public struct CloudHeartbeatResponse: Codable, Sendable, Equatable {
    public var serverTime: Date
    public var policyVersion: Int
    /// The device holds an older policy version: fetch it (a missed `policyChanged`).
    public var policyStale: Bool
    public var pendingEvents: Int
}

/// `POST /api/v1/device/usage`: today's snapshot, plus yesterday's last one
/// after a day rollover. The server buckets each by the child's local date.
public struct CloudUsageUpload: Codable, Sendable, Equatable {
    public var timeZone: String
    public var days: [UsageTransfer]

    public init(timeZone: String, days: [UsageTransfer]) {
        self.timeZone = timeZone
        self.days = days
    }
}

/// `GET /api/v1/device/events`
public struct CloudEventsResponse: Decodable, Sendable, Equatable {
    public var events: [CloudEvent]
    public var nextCursor: Int
    public var serverTime: Date
    /// Set when the server is busy: wait this long before polling again.
    public var retryAfter: Int?
}

/// Reply to `POST`/`DELETE /api/v1/device/extension-requests`.
public struct CloudExtensionReceipt: Codable, Sendable, Equatable {
    public var requestId: UUID
    public var status: String
    public var requestedMinutes: Int
    public var grantedMinutes: Int?
    public var grantedUntil: Date?
    public var createdAt: Date?
}

/// Error body of every non-2xx device API reply, e.g. `{"error":"device_revoked"}`.
public struct CloudErrorBody: Codable, Sendable, Equatable {
    public var error: String

    public static let invalidToken = "invalid_token"
    public static let deviceRevoked = "device_revoked"
    public static let invalidCode = "invalid_code"
}

/// Reply to `POST /api/v1/device/token/rotate`.
public struct CloudTokenRotation: Codable, Sendable, Equatable {
    public var deviceToken: String
    public var rotatedAt: Date
}
