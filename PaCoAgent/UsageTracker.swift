import Foundation
import PaCoShared

final class UsageTracker {

    private let logger = PaCoLogger.agent
    private var appStartTimes: [String: Date] = [:]  // bundleId -> launch time
    private var dailyUsage: [String: AppUsageEntry] = [:]  // bundleId -> aggregated
    private var internetOnSince: Date?
    private var totalInternetSeconds: TimeInterval = 0
    private var currentDate: Date

    init() {
        self.currentDate = Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Internet tracking

    func internetDidEnable() {
        internetOnSince = Date()
        logger.info("Tracking: internet enabled")
    }

    func internetDidDisable() {
        if let since = internetOnSince {
            totalInternetSeconds += Date().timeIntervalSince(since)
            internetOnSince = nil
        }
        let total = Int(totalInternetSeconds)
        logger.info("Tracking: internet disabled, total: \(total)s")
    }

    // MARK: - App tracking

    func appDidLaunch(bundleId: String, appName: String) {
        rollDateIfNeeded()
        appStartTimes[bundleId] = Date()

        // Increment launch count
        var entry = dailyUsage[bundleId] ?? AppUsageEntry(
            bundleIdentifier: bundleId, appName: appName, duration: 0, launchCount: 0
        )
        entry.launchCount += 1
        dailyUsage[bundleId] = entry
    }

    func appDidTerminate(bundleId: String, appName: String) {
        rollDateIfNeeded()
        guard let startTime = appStartTimes.removeValue(forKey: bundleId) else { return }
        let duration = Date().timeIntervalSince(startTime)

        var entry = dailyUsage[bundleId] ?? AppUsageEntry(
            bundleIdentifier: bundleId, appName: appName, duration: 0, launchCount: 0
        )
        entry.duration += duration
        dailyUsage[bundleId] = entry
    }

    // MARK: - Reporting

    func currentInternetDuration() -> TimeInterval {
        var total = totalInternetSeconds
        if let since = internetOnSince {
            total += Date().timeIntervalSince(since)
        }
        return total
    }

    func currentAppUsage() -> [AppUsageEntry] {
        Array(dailyUsage.values)
    }

    func buildUsageRecord(for profileId: UUID) -> UsageRecord {
        return UsageRecord(
            date: currentDate,
            internetOnDuration: currentInternetDuration(),
            appUsage: currentAppUsage()
        )
    }

    func reset() {
        appStartTimes.removeAll()
        dailyUsage.removeAll()
        internetOnSince = nil
        totalInternetSeconds = 0
        currentDate = Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Private

    private func rollDateIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != currentDate {
            logger.info("Day rolled over, resetting usage counters")
            reset()
            currentDate = today
        }
    }
}
