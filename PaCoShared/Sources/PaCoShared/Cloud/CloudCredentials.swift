import Foundation

/// The daemon's PaCo Cloud enrollment, persisted root-only (0600) at
/// `/Library/Application Support/PaCo/cloud.json`. The device token is the
/// device's only credential; the monitored user can neither read nor replace it.
public struct CloudCredentials: Codable, Sendable, Equatable {
    public static let defaultPath = "/Library/Application Support/PaCo/cloud.json"

    public var serverURL: URL
    public var deviceId: UUID
    public var deviceName: String
    public var deviceToken: String
    /// Id of the last event applied; sent as the long-poll cursor (= acknowledgement).
    public var eventCursor: Int
    /// Version of the last policy envelope applied (0 = none yet).
    public var policyVersion: Int
    /// Resolved addresses of the server host, allowed through the `pf` block so the
    /// device stays reachable while internet is off (DNS is blocked then too).
    public var relayAddresses: [String]
    public var relayResolvedAt: Date?
    public var enrolledAt: Date
    /// When the current token was issued (nil: at enrollment). Rotated every
    /// `tokenLifetime`; the server keeps the old one valid until the new one is used.
    public var tokenIssuedAt: Date?

    public static let tokenLifetime: TimeInterval = 30 * 24 * 3600

    public init(
        serverURL: URL,
        deviceId: UUID,
        deviceName: String,
        deviceToken: String,
        eventCursor: Int = 0,
        policyVersion: Int = 0,
        relayAddresses: [String] = [],
        relayResolvedAt: Date? = nil,
        enrolledAt: Date = Date(),
        tokenIssuedAt: Date? = nil
    ) {
        self.serverURL = serverURL
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceToken = deviceToken
        self.eventCursor = eventCursor
        self.policyVersion = policyVersion
        self.relayAddresses = relayAddresses
        self.relayResolvedAt = relayResolvedAt
        self.enrolledAt = enrolledAt
        self.tokenIssuedAt = tokenIssuedAt
    }

    public func needsTokenRotation(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(tokenIssuedAt ?? enrolledAt) >= Self.tokenLifetime
    }

    /// The TCP port the server listens on (for the `pf` pass rule).
    public var serverPort: Int {
        if let port = serverURL.port { return port }
        return serverURL.scheme?.lowercased() == "http" ? 80 : 443
    }

    public var relay: CloudRelay {
        CloudRelay(addresses: relayAddresses, port: serverPort)
    }

    public static func load(from url: URL) -> CloudCredentials? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CloudCodec.decode(CloudCredentials.self, from: data)
    }

    public func save(to url: URL) throws {
        try SecureFile.write(try CloudCodec.encode(self), to: url, permissions: 0o600)
    }

    public static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Atomic write of a file that is never readable by others, not even briefly:
/// the temporary file is created with the final permissions, then renamed.
public enum SecureFile {
    public enum WriteError: Error, Equatable {
        case create(errno: Int32)
        case write(errno: Int32)
        case rename(errno: Int32)
    }

    public static func write(_ data: Data, to url: URL, permissions: mode_t) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")

        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, permissions)
        guard fd >= 0 else { throw WriteError.create(errno: errno) }
        // `open` applies the umask; force the exact mode.
        fchmod(fd, permissions)

        let written = data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, base + offset, buffer.count - offset)
                if n <= 0 { return -1 }
                offset += n
            }
            return offset
        }
        let writeErrno = errno
        fsync(fd)
        close(fd)
        guard written == data.count else {
            unlink(temp.path)
            throw WriteError.write(errno: writeErrno)
        }
        guard rename(temp.path, url.path) == 0 else {
            let renameErrno = errno
            unlink(temp.path)
            throw WriteError.rename(errno: renameErrno)
        }
    }
}
