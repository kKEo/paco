// PaCoAgent/AppMonitor.swift
import AppKit
import Foundation
import PaCoShared

protocol AppMonitorDelegate: AnyObject {
    func appMonitor(_ monitor: AppMonitor, didDetectBlockedApp bundleId: String, pid: Int32, appName: String)
    func appMonitor(_ monitor: AppMonitor, checkScheduledApp bundleId: String, pid: Int32, appName: String, allowedScheduleId: UUID?)
    /// A regular (Dock) app came to the foreground; nil when none is frontmost.
    func appMonitor(_ monitor: AppMonitor, didActivateApp bundleId: String?, appName: String?)
    func appMonitor(_ monitor: AppMonitor, didLaunchApp bundleId: String, appName: String)
    func appMonitor(_ monitor: AppMonitor, didTerminateApp bundleId: String, appName: String)
}

final class AppMonitor {

    weak var delegate: AppMonitorDelegate?
    private let logger = PaCoLogger.agent
    private var restrictions: [AppRestrictionTransfer] = []
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
        center.addObserver(
            self, selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        // Whatever is frontmost when the agent starts counts from now.
        reportActivation(of: workspace.frontmostApplication)

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

    func updateRestrictions(_ restrictions: [AppRestrictionTransfer]) {
        self.restrictions = restrictions
        checkRunningApps()
    }

    // MARK: - Notification handlers

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        let appName = app.localizedName ?? bundleId
        // Usage counts only real (Dock) apps, not helpers and agents; restrictions apply to anything.
        if app.activationPolicy == .regular {
            delegate?.appMonitor(self, didLaunchApp: bundleId, appName: appName)
        }
        checkApp(bundleId: bundleId, pid: app.processIdentifier, appName: appName)
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        let appName = app.localizedName ?? bundleId
        delegate?.appMonitor(self, didTerminateApp: bundleId, appName: appName)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        reportActivation(of: notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }

    private func reportActivation(of app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular, let bundleId = app.bundleIdentifier else {
            delegate?.appMonitor(self, didActivateApp: nil, appName: nil)
            return
        }
        delegate?.appMonitor(self, didActivateApp: bundleId, appName: app.localizedName ?? bundleId)
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
            delegate?.appMonitor(self, checkScheduledApp: bundleId, pid: pid, appName: appName,
                                 allowedScheduleId: restriction.allowedScheduleId)
        }
    }
}
