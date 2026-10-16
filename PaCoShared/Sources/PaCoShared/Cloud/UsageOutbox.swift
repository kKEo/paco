import Foundation

/// Usage snapshots waiting to be uploaded (pure, unit-tested).
///
/// The agent reports today's running totals every 30 s. The daemon uploads the
/// newest one at most every `minInterval`, and immediately after a day rollover
/// so the finished day's final totals are not lost. A day stays pending until an
/// upload containing exactly that snapshot succeeds.
public struct UsageOutbox: Sendable, Equatable {
    public static let defaultMinInterval: TimeInterval = 300

    /// Pending snapshots, oldest day first; at most one per day, at most `maxDays`.
    public private(set) var pending: [UsageTransfer] = []
    public private(set) var lastUploadAt: Date?
    private var rolledOver = false

    public static let maxDays = 3

    public init() {}

    /// Record the agent's latest snapshot; it replaces any older snapshot of the same day.
    public mutating func record(_ snapshot: UsageTransfer) {
        if let index = pending.firstIndex(where: { $0.date == snapshot.date }) {
            pending[index] = snapshot
        } else {
            if let last = pending.last, last.date < snapshot.date { rolledOver = true }
            pending.append(snapshot)
            pending.sort { $0.date < $1.date }
            if pending.count > Self.maxDays { pending.removeFirst(pending.count - Self.maxDays) }
        }
    }

    public func shouldUpload(now: Date, minInterval: TimeInterval = UsageOutbox.defaultMinInterval) -> Bool {
        guard !pending.isEmpty else { return false }
        if rolledOver { return true }
        guard let lastUploadAt else { return true }
        return now.timeIntervalSince(lastUploadAt) >= minInterval
    }

    /// After a successful upload of `uploaded`: drop the days whose snapshot did
    /// not change meanwhile. Today's entry stays only if a newer snapshot arrived
    /// during the upload; it is re-sent at the next interval anyway.
    public mutating func markUploaded(_ uploaded: [UsageTransfer], at date: Date) {
        pending.removeAll { uploaded.contains($0) }
        lastUploadAt = date
        rolledOver = false
    }

    /// After a failed upload: retry at the next interval rather than every tick.
    public mutating func markFailed(at date: Date) {
        lastUploadAt = date
    }
}
