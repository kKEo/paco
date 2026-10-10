// PaCo/Services/SyncManager.swift
import Foundation
import SwiftData
import PaCoShared

/// Turns the parent's persisted policy (schedules, app restrictions) into a
/// `PolicyTransfer` and hands it to `onPolicyChanged`, which the app delegate
/// pushes to the local root daemon and to connected child Macs. Also imports the
/// agent's usage snapshot.
///
/// Policy is never written to a user-level file any more: the daemon keeps the
/// only copy, under a root-owned path, so the monitored user cannot edit it.
///
/// Sync methods always fetch fresh from the `ModelContext` rather than taking an
/// array from a view: a `@Query` array captured in a button action still reflects
/// the state *before* the insert/delete, which left enforcement one change behind.
final class SyncManager {

    static let shared = SyncManager()
    private init() {}

    private let logger = PaCoLogger.app

    /// Parent side: invoked with the full policy after any schedule/restriction change.
    var onPolicyChanged: ((PolicyTransfer) -> Void)?

    var usageFileURL: URL { PaCoFiles.usageFileURL }

    /// The policy as it should be enforced right now.
    func currentPolicy(context: ModelContext) -> PolicyTransfer {
        // Inactive schedules travel too (the evaluator skips them): an app rule that
        // follows a disabled schedule must resolve it and be lenient, not blocked.
        let schedules = ((try? context.fetch(FetchDescriptor<Schedule>())) ?? [])
            .map(ScheduleTransfer.init(from:))
        let restrictions = ((try? context.fetch(FetchDescriptor<AppRestriction>())) ?? [])
            .map(AppRestrictionTransfer.init(from:))
        return PolicyTransfer(schedules: schedules, restrictions: restrictions)
    }

    /// Publish the current policy. Schedules and restrictions always travel
    /// together, so the three entry points are equivalent; they exist so call
    /// sites read naturally.
    func syncAll(context: ModelContext) {
        let policy = currentPolicy(context: context)
        logger.info("Publishing policy: \(policy.schedules.count) schedules, \(policy.restrictions.count) restrictions")
        onPolicyChanged?(policy)
    }

    func syncSchedules(context: ModelContext) { syncAll(context: context) }
    func syncRestrictions(context: ModelContext) { syncAll(context: context) }

    // MARK: - Usage (read from agent-written file)

    func readUsage(context: ModelContext) {
        guard let data = try? Data(contentsOf: usageFileURL),
              let transfer = try? JSONDecoder().decode(UsageTransfer.self, from: data)
        else { return }

        let today = Calendar.current.startOfDay(for: transfer.date)

        var profile: ChildProfile? = nil
        if let pid = transfer.profileId {
            let allProfiles = (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []
            profile = allProfiles.first(where: { $0.id == pid })
        }

        let allRecords = (try? context.fetch(FetchDescriptor<UsageRecord>())) ?? []
        let existing = allRecords.first { record in
            Calendar.current.isDate(record.date, inSameDayAs: today)
            && (transfer.profileId == nil || record.childProfile?.id == transfer.profileId)
        }

        if let record = existing {
            record.internetOnDuration = transfer.internetOnDuration
            record.appUsage = transfer.appUsage
        } else {
            let record = UsageRecord(date: today, internetOnDuration: transfer.internetOnDuration, appUsage: transfer.appUsage)
            record.childProfile = profile
            context.insert(record)
        }

        try? context.save()
    }
}
