// PaCo/Services/SyncManager.swift
import Foundation
import SwiftData
import PaCoShared

/// Writes the enforcement policy (schedules, restrictions, active profile) to the
/// shared JSON files the agent reads, and imports the agent's usage snapshot.
///
/// On a **parent** Mac the policy comes from SwiftData and every write also fires
/// `onPolicyChanged`, which the app uses to push the same policy to connected
/// child Macs. On a **child** Mac the policy arrives over Bonjour and is written
/// with `applyRemotePolicy`; the child never serializes its own (empty) SwiftData
/// policy, or it would wipe what the parent pushed.
///
/// Sync methods always fetch fresh from the `ModelContext` rather than taking an
/// array from a view: a `@Query` array captured in a button action still reflects
/// the state *before* the insert/delete, which left the agent one change behind.
final class SyncManager {

    static let shared = SyncManager()
    private init() {}

    private let logger = PaCoLogger.app

    /// Parent side: invoked after schedules or restrictions were written.
    var onPolicyChanged: (() -> Void)?

    var usageFileURL: URL { PaCoFiles.usageFileURL }
    /// Forward to PaCoFiles for callers that hold a SyncManager reference (e.g. ChildModeView).
    var eventsFileURL: URL { PaCoFiles.eventsFileURL }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: PaCoFiles.baseDirectory, withIntermediateDirectories: true)
    }

    /// Parent: write every policy file from the current persisted state.
    func syncAll(context: ModelContext) {
        syncSchedules(context: context)
        syncRestrictions(context: context)
        let config = (try? context.fetch(FetchDescriptor<DeviceConfig>()))?.first
        syncDeviceConfig(activeProfileId: config?.childProfileId)
    }

    /// The policy as it would be written to disk / pushed to a child.
    func currentPolicy(context: ModelContext) -> PolicyTransfer {
        let schedules = ((try? context.fetch(FetchDescriptor<Schedule>())) ?? [])
            .filter(\.isActive).map(ScheduleTransfer.init(from:))
        let restrictions = ((try? context.fetch(FetchDescriptor<AppRestriction>())) ?? [])
            .map(AppRestrictionTransfer.init(from:))
        return PolicyTransfer(schedules: schedules, restrictions: restrictions)
    }

    // MARK: - Schedules

    func syncSchedules(context: ModelContext) {
        do {
            let schedules = try context.fetch(FetchDescriptor<Schedule>())
            try writeSchedules(schedules.filter(\.isActive).map(ScheduleTransfer.init(from:)))
            onPolicyChanged?()
        } catch {
            logger.error("Failed to sync schedules: \(error)")
        }
    }

    // MARK: - App Restrictions

    func syncRestrictions(context: ModelContext) {
        do {
            let restrictions = try context.fetch(FetchDescriptor<AppRestriction>())
            try writeRestrictions(restrictions.map(AppRestrictionTransfer.init(from:)))
            onPolicyChanged?()
        } catch {
            logger.error("Failed to sync restrictions: \(error)")
        }
    }

    // MARK: - Remote policy (child side)

    /// Child: persist the policy pushed by the parent for the local agent.
    func applyRemotePolicy(_ policy: PolicyTransfer) -> Bool {
        do {
            try writeSchedules(policy.schedules)
            try writeRestrictions(policy.restrictions)
            return true
        } catch {
            logger.error("Failed to apply remote policy: \(error)")
            return false
        }
    }

    private func writeSchedules(_ transfers: [ScheduleTransfer]) throws {
        try prepare()
        let data = try JSONEncoder().encode(transfers)
        try data.write(to: PaCoFiles.schedulesFileURL, options: .atomic)
        logger.info("Wrote \(transfers.count) schedules")
    }

    private func writeRestrictions(_ transfers: [AppRestrictionTransfer]) throws {
        try prepare()
        let data = try JSONEncoder().encode(transfers)
        try data.write(to: PaCoFiles.restrictionsFileURL, options: .atomic)
        logger.info("Wrote \(transfers.count) app restrictions")
    }

    // MARK: - Device config (active profile)

    func syncDeviceConfig(activeProfileId: UUID?) {
        do {
            try prepare()
            let transfer = DeviceConfigTransfer(activeProfileId: activeProfileId)
            let data = try JSONEncoder().encode(transfer)
            try data.write(to: PaCoFiles.configFileURL, options: .atomic)
            logger.info("Synced device config, activeProfileId=\(activeProfileId?.uuidString ?? "nil")")
        } catch {
            logger.error("Failed to sync device config: \(error)")
        }
    }

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
