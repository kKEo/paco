// PaCo/Services/SyncManager.swift
import Foundation
import PaCoShared

final class SyncManager {

    static let shared = SyncManager()
    private init() {}

    private let logger = PaCoLogger.app

    private var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.paco")
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    // MARK: - Schedules

    func syncSchedules(_ schedules: [Schedule]) {
        do {
            try prepare()
            let transfers = schedules.filter(\.isActive).map(ScheduleTransfer.init(from:))
            let data = try JSONEncoder().encode(transfers)
            try data.write(to: baseURL.appendingPathComponent("schedules.json"), options: .atomic)
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
            try data.write(to: baseURL.appendingPathComponent("restrictions.json"), options: .atomic)
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
            try data.write(to: baseURL.appendingPathComponent("config.json"), options: .atomic)
            logger.info("Synced device config, activeProfileId=\(activeProfileId?.uuidString ?? "nil")")
        } catch {
            logger.error("Failed to sync device config: \(error)")
        }
    }
}
