import Foundation

/// Pure accounting of per-app *foreground* time and launch counts for one day.
/// The agent feeds it activation/launch/termination events from NSWorkspace;
/// this type knows nothing about AppKit so it can be unit-tested.
///
/// Time accrues for whichever app is frontmost, including while it is still
/// open (`snapshot` closes the running interval up to "now"), so the dashboard
/// does not show zero until the app quits.
public struct UsageLedger: Equatable, Sendable {

    private var entries: [String: AppUsageEntry] = [:]
    private var foregroundBundleId: String?
    private var foregroundSince: Date?

    public init() {}

    /// Seed from a saved snapshot (same day).
    public init(entries: [AppUsageEntry]) {
        for entry in entries { self.entries[entry.bundleIdentifier] = entry }
    }

    public var currentForegroundBundleId: String? { foregroundBundleId }

    // MARK: - Events

    /// `bundleId` became frontmost at `date`. Pass nil when no tracked app is frontmost.
    public mutating func activate(bundleId: String?, appName: String? = nil, at date: Date = Date()) {
        flush(at: date)
        foregroundBundleId = bundleId
        foregroundSince = bundleId == nil ? nil : date
        if let bundleId, entries[bundleId] == nil {
            entries[bundleId] = AppUsageEntry(bundleIdentifier: bundleId, appName: appName ?? bundleId, duration: 0, launchCount: 0)
        }
    }

    public mutating func launch(bundleId: String, appName: String) {
        var entry = entries[bundleId] ?? AppUsageEntry(bundleIdentifier: bundleId, appName: appName, duration: 0, launchCount: 0)
        entry.launchCount += 1
        entry.appName = appName
        entries[bundleId] = entry
    }

    public mutating func terminate(bundleId: String, at date: Date = Date()) {
        guard foregroundBundleId == bundleId else { return }
        flush(at: date)
        foregroundBundleId = nil
        foregroundSince = nil
    }

    /// Fold the running foreground interval into the totals.
    public mutating func flush(at date: Date = Date()) {
        guard let bundleId = foregroundBundleId, let since = foregroundSince else { return }
        let elapsed = max(0, date.timeIntervalSince(since))
        entries[bundleId]?.duration += elapsed
        foregroundSince = date
    }

    /// Start a new day: totals reset, the current foreground app keeps accruing from `date`.
    public mutating func reset(at date: Date = Date()) {
        entries = [:]
        if let bundleId = foregroundBundleId {
            entries[bundleId] = AppUsageEntry(bundleIdentifier: bundleId, appName: bundleId, duration: 0, launchCount: 0)
            foregroundSince = date
        }
    }

    // MARK: - Reporting

    /// Totals including the still-open foreground interval, as of `date`.
    public func snapshot(at date: Date = Date()) -> [AppUsageEntry] {
        var copy = self
        copy.flush(at: date)
        return copy.entries.values.sorted { $0.duration > $1.duration }
    }
}
