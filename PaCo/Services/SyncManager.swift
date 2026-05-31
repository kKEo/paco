// PaCo/Services/SyncManager.swift
import Foundation
import SwiftData
import PaCoShared

final class SyncManager {

    static let shared = SyncManager()
    private init() {}

    private let logger = PaCoLogger.app

    var usageFileURL: URL { PaCoFiles.usageFileURL }
    /// Forward to PaCoFiles for callers that hold a SyncManager reference (e.g. ChildModeView).
    var eventsFileURL: URL { PaCoFiles.eventsFileURL }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: PaCoFiles.baseDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Schedules

    func syncSchedules(_ schedules: [Schedule]) {
        do {
            try prepare()
            let transfers = schedules.filter(\.isActive).map(ScheduleTransfer.init(from:))
            let data = try JSONEncoder().encode(transfers)
            try data.write(to: PaCoFiles.schedulesFileURL, options: .atomic)
            logger.info("Synced \(transfers.count) schedules")
        } catch {
            logger.error("Failed to sync schedules: \(error)")
        }
    }

    // MARK: - App Restrictions

    func syncRestrictions(_ restrictions: [AppRestriction]) {
        do {
            try prepare()
            let transfers = restrictions.map(AppRestrictionTransfer.init(from:))
            let data = try JSONEncoder().encode(transfers)
            try data.write(to: PaCoFiles.restrictionsFileURL, options: .atomic)
            logger.info("Synced \(transfers.count) app restrictions")
        } catch {
            logger.error("Failed to sync restrictions: \(error)")
        }
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
