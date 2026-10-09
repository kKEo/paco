import Foundation
import PaCoShared

/// Child-side, observable view of the sent time-extension requests and their
/// outcomes, persisted to `child-requests.json` so a pending request survives an
/// app relaunch and its late approval is still accepted (see `ChildRequestStore`).
///
/// All access happens on the main queue (Bonjour callbacks and views both run there).
final class ChildRequestLog: ObservableObject {
    static let shared = ChildRequestLog()

    @Published private(set) var store: ChildRequestStore

    /// Unanswered requests older than this are dropped on load: the parent is
    /// not going to answer them and they would block a new request forever.
    private static let pendingMaxAge: TimeInterval = 24 * 3600

    private let fileURL = PaCoFiles.childRequestsFileURL
    private let logger = PaCoLogger.app

    private init() {
        var loaded = ChildRequestStore.load(from: PaCoFiles.childRequestsFileURL)
        loaded.expirePending(olderThan: Self.pendingMaxAge)
        store = loaded
    }

    var pending: ChildRequestRecord? { store.pending }
    var latest: ChildRequestRecord? { store.latest }

    func record(id: UUID, requestedMinutes: Int, reason: String) {
        store.record(id: id, requestedMinutes: requestedMinutes, reason: reason)
        persist()
    }

    /// Resolve an outstanding request; false if unknown or already resolved (replay).
    @discardableResult
    func resolve(id: UUID, approved: Bool, grantedUntil: Date? = nil) -> Bool {
        guard store.resolve(id: id, approved: approved, grantedUntil: grantedUntil) else { return false }
        persist()
        return true
    }

    /// Give up on the outstanding request so a new one can be sent.
    func withdrawPending() {
        store.withdrawPending()
        persist()
    }

    private func persist() {
        do {
            try store.save(to: fileURL)
        } catch {
            logger.error("Failed to save child request log: \(error)")
        }
    }
}
