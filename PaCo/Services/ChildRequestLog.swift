import Foundation

/// Child-side record of extension request IDs this device has sent, so an
/// incoming approval/denial can be correlated to a real outstanding request
/// (defense-in-depth on top of the authenticated TLS-PSK channel).
final class ChildRequestLog {
    static let shared = ChildRequestLog()
    private init() {}

    private let lock = NSLock()
    private var sentIds: Set<UUID> = []

    func record(_ id: UUID) {
        lock.lock(); sentIds.insert(id); lock.unlock()
    }

    /// True if `id` matches an outstanding request; consumes it so it can't be replayed.
    func consume(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sentIds.remove(id) != nil
    }
}
