import AppKit
import Foundation
import PaCoShared

protocol AppMonitorDelegate: AnyObject {
    func appMonitor(_ monitor: AppMonitor, didDetectBlockedApp bundleId: String, pid: Int32, appName: String)
    func appMonitor(_ monitor: AppMonitor, didLaunchApp bundleId: String, appName: String)
    func appMonitor(_ monitor: AppMonitor, didTerminateApp bundleId: String, appName: String)
}

final class AppMonitor {

    weak var delegate: AppMonitorDelegate?
    private let logger = PaCoLogger.agent
    private var restrictions: [AppRestriction] = []
    private var schedules: [Schedule] = []
    private var pollingTimer: Timer?

    func start() {
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter

        center.addObserver(
            self, selector: #selector(appDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(appDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )

        // Polling fallback every 10 seconds
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkRunningApps()
        }

        logger.info("AppMonitor started")
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pollingTimer?.invalidate()
        pollingTimer = nil
        logger.info("AppMonitor stopped")
    }

    func updateRestrictions(_ restrictions: [AppRestriction], schedules: [Schedule]) {
        self.restrictions = restrictions
        self.schedules = schedules
        // Re-check currently running apps against new restrictions
        checkRunningApps()
    }

    // MARK: - Notification handlers

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        let appName = app.localizedName ?? bundleId
        delegate?.appMonitor(self, didLaunchApp: bundleId, appName: appName)
        checkApp(bundleId: bundleId, pid: app.processIdentifier, appName: appName)
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        let appName = app.localizedName ?? bundleId
        delegate?.appMonitor(self, didTerminateApp: bundleId, appName: appName)
    }

    // MARK: - Restriction checking

    private func checkRunningApps() {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleId = app.bundleIdentifier else { continue }
            let appName = app.localizedName ?? bundleId
            checkApp(bundleId: bundleId, pid: app.processIdentifier, appName: appName)
        }
    }

    private func checkApp(bundleId: String, pid: Int32, appName: String) {
        guard let restriction = restrictions.first(where: { $0.bundleIdentifier == bundleId }) else {
            return
        }

        switch restriction.restrictionType {
        case .blocked:
            logger.info("Blocked app detected: \(appName) (\(bundleId))")
            delegate?.appMonitor(self, didDetectBlockedApp: bundleId, pid: pid, appName: appName)

        case .scheduledOnly:
            // Check if we're in the allowed schedule
            if let scheduleId = restriction.allowedScheduleId,
               let schedule = schedules.first(where: { $0.id == scheduleId }) {
                let action = ScheduleEvaluator.evaluate(schedules: [schedule], at: Date())
                if action != .allowed {
                    logger.info("App outside schedule: \(appName) (\(bundleId))")
                    delegate?.appMonitor(self, didDetectBlockedApp: bundleId, pid: pid, appName: appName)
                }
            }
        }
    }
}
