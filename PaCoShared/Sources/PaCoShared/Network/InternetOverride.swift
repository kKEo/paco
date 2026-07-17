import Foundation

/// A temporary "allow internet until <expiry>" grant that supersedes schedule
/// blocking. Written when a parent approves a time-extension request and read by
/// the agent on every tick. This is what makes an approved extension actually
/// grant time (and expire) instead of being reverted on the next schedule tick.
public struct InternetOverride: Codable, Sendable, Equatable {
    public var requestId: UUID
    public var grantedUntil: Date

    public init(requestId: UUID, grantedUntil: Date) {
        self.requestId = requestId
        self.grantedUntil = grantedUntil
    }

    public var isActive: Bool { grantedUntil > Date() }
}

/// Single-writer helper for the override file. The approving side writes; the
/// agent reads. Atomic writes keep it torn-free.
public enum OverrideStore {

    public static func write(_ override: InternetOverride) {
        guard let data = try? JSONEncoder().encode(override) else { return }
        try? FileManager.default.createDirectory(at: PaCoFiles.baseDirectory, withIntermediateDirectories: true)
        try? data.write(to: PaCoFiles.overrideFileURL, options: .atomic)
    }

    public static func read() -> InternetOverride? {
        guard let data = try? Data(contentsOf: PaCoFiles.overrideFileURL),
              let override = try? JSONDecoder().decode(InternetOverride.self, from: data) else {
            return nil
        }
        return override
    }

    /// The active override expiry, or nil if none/expired.
    public static func activeUntil() -> Date? {
        guard let override = read(), override.isActive else { return nil }
        return override.grantedUntil
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: PaCoFiles.overrideFileURL)
    }
}
