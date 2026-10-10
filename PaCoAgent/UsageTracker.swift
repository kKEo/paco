import Foundation
import PaCoShared

/// Day-scoped usage counters: internet-on time and per-app foreground time
/// (`UsageLedger`). Restored from the last snapshot on start so an agent restart
/// mid-day continues accumulating instead of resetting to zero.
final class UsageTracker {

    private let logger = PaCoLogger.agent
    private var ledger = UsageLedger()
    private var internetOnSince: Date?
    private var totalInternetSeconds: TimeInterval = 0
    private var currentDate: Date

    init() {
        self.currentDate = Calendar.current.startOfDay(for: Date())
        restoreFromSnapshot()
    }

    private func restoreFromSnapshot() {
        guard let data = try? Data(contentsOf: PaCoFiles.usageFileURL),
              let transfer = try? JSONDecoder().decode(UsageTransfer.self, from: data),
              Calendar.current.isDate(transfer.date, inSameDayAs: currentDate) else {
            return
        }
        totalInternetSeconds = transfer.internetOnDuration
        ledger = UsageLedger(entries: transfer.appUsage)
        logger.info("Restored usage snapshot: \(transfer.appUsage.count) apps, internet \(Int(self.totalInternetSeconds))s")
    }

    // MARK: - Internet tracking

    func internetDidEnable() {
        rollDateIfNeeded()
        internetOnSince = Date()
        logger.info("Tracking: internet enabled")
    }

    func internetDidDisable() {
        rollDateIfNeeded()
        if let since = internetOnSince {
            totalInternetSeconds += Date().timeIntervalSince(since)
            internetOnSince = nil
        }
        let total = Int(totalInternetSeconds)
        logger.info("Tracking: internet disabled, total: \(total)s")
    }

    // MARK: - App tracking (foreground time)

    func appDidActivate(bundleId: String?, appName: String?) {
        rollDateIfNeeded()
        ledger.activate(bundleId: bundleId, appName: appName)
    }

    func appDidLaunch(bundleId: String, appName: String) {
        rollDateIfNeeded()
        ledger.launch(bundleId: bundleId, appName: appName)
    }

    func appDidTerminate(bundleId: String, appName: String) {
        rollDateIfNeeded()
        ledger.terminate(bundleId: bundleId)
    }

    // MARK: - Reporting

    func currentInternetDuration() -> TimeInterval {
        var total = totalInternetSeconds
        if let since = internetOnSince {
            total += Date().timeIntervalSince(since)
        }
        return total
    }

    var currentDay: Date { currentDate }

    func currentAppUsage() -> [AppUsageEntry] {
        rollDateIfNeeded()
        return ledger.snapshot()
    }

    // MARK: - Private

    /// At midnight the counters start over; whatever is frontmost keeps accruing
    /// into the new day and an open internet-on interval restarts from now.
    private func rollDateIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        guard today != currentDate else { return }
        logger.info("Day rolled over, resetting usage counters")
        ledger.reset()
        totalInternetSeconds = 0
        if internetOnSince != nil { internetOnSince = Date() }
        currentDate = today
    }
}
