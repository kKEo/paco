// PaCoAgent/AgentDelegate.swift
import Foundation
import PaCoShared

/// The user-level agent is a *reporter*: it watches the user's running apps,
/// asks the daemon to kill restricted ones, and keeps the usage snapshot. It no
/// longer decides anything about the internet: the root daemon owns the policy
/// and evaluates it itself (see `PolicyEngine`), so nothing the monitored user
/// can edit influences enforcement. The agent reads that policy over XPC each
/// tick to know which apps to watch.
final class AgentDelegate: NSObject, AppMonitorDelegate {

    private let appMonitor = AppMonitor()
    private let usageTracker = UsageTracker()
    private var scheduleTimer: DispatchSourceTimer?
    private var daemonConnection: NSXPCConnection?
    private let logger = PaCoLogger.agent
    private var currentPolicy: DaemonPolicy = .empty
    /// Last internet state observed from the daemon, so usage tracking and events
    /// react only to changes (edge-trigger).
    private var lastObservedInternetEnabled: Bool?

    func start() {
        appMonitor.delegate = self
        appMonitor.start()
        connectToDaemon()
        startTickTimer()
        logger.info("AgentDelegate started")
    }

    // MARK: - Daemon XPC connection

    private func connectToDaemon() {
        let connection = NSXPCConnection(machServiceName: "com.paco.daemon", options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: DaemonXPCProtocol.self)
        connection.interruptionHandler = { [weak self] in
            self?.logger.warning("Daemon XPC connection interrupted; will re-sync on next tick")
            DispatchQueue.main.async { self?.lastObservedInternetEnabled = nil }
        }
        connection.invalidationHandler = { [weak self] in
            self?.logger.warning("Daemon XPC connection invalidated, reconnecting...")
            DispatchQueue.main.async { self?.lastObservedInternetEnabled = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.connectToDaemon() }
        }
        connection.resume()
        daemonConnection = connection
        logger.info("Connected to daemon via XPC")
    }

    private var daemonProxy: DaemonXPCProtocol? {
        daemonConnection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.logger.error("Daemon XPC error: \(error.localizedDescription)")
        } as? DaemonXPCProtocol
    }

    // MARK: - Tick

    private func startTickTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 30)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        scheduleTimer = timer
    }

    private func tick() {
        daemonProxy?.fetchPolicy { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, let policy = try? JSONDecoder().decode(DaemonPolicy.self, from: data) {
                    self.currentPolicy = policy
                    self.appMonitor.updateRestrictions(policy.activeRestrictions)
                }
                self.writeUsage(profileId: self.currentPolicy.activeProfileId)
            }
        }
        daemonProxy?.isInternetEnabled { [weak self] enabled in
            DispatchQueue.main.async { self?.observeInternet(enabled: enabled) }
        }
    }

    /// Track internet on/off time and emit events when the daemon's state changes.
    private func observeInternet(enabled: Bool) {
        guard lastObservedInternetEnabled != enabled else { return }
        lastObservedInternetEnabled = enabled
        if enabled {
            usageTracker.internetDidEnable()
            appendEvent(NotificationEvent(kind: .internetEnabled))
        } else {
            usageTracker.internetDidDisable()
            appendEvent(NotificationEvent(kind: .internetDisabled))
        }
        logger.info("Observed internet \(enabled ? "enabled" : "disabled")")
    }

    private func appendEvent(_ event: NotificationEvent) {
        var events: [NotificationEvent] = []
        if let data = try? Data(contentsOf: PaCoFiles.eventsFileURL),
           let existing = try? JSONDecoder().decode([NotificationEvent].self, from: data) {
            events = existing
        }
        events.append(event)
        if events.count > 100 { events = Array(events.suffix(100)) }
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? FileManager.default.createDirectory(at: PaCoFiles.baseDirectory, withIntermediateDirectories: true)
        try? data.write(to: PaCoFiles.eventsFileURL, options: .atomic)
    }

    private func writeUsage(profileId: UUID?) {
        let transfer = UsageTransfer(
            date: usageTracker.currentDay,
            profileId: profileId,
            internetOnDuration: usageTracker.currentInternetDuration(),
            appUsage: usageTracker.currentAppUsage()
        )
        guard let data = try? JSONEncoder().encode(transfer) else { return }
        try? FileManager.default.createDirectory(at: PaCoFiles.baseDirectory, withIntermediateDirectories: true)
        try? data.write(to: PaCoFiles.usageFileURL, options: .atomic)
        // The daemon uploads it to PaCo Cloud when this Mac is enrolled (else ignores it).
        daemonProxy?.reportUsage(data) { _ in }
    }

    // MARK: - AppMonitorDelegate

    func appMonitor(_ monitor: AppMonitor, didDetectBlockedApp bundleId: String, pid: Int32, appName: String) {
        daemonProxy?.killProcess(pid: pid) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.logger.info("Killed blocked app: \(appName)")
                    self?.appendEvent(NotificationEvent(kind: .appBlocked, payload: ["appName": appName, "bundleId": bundleId]))
                    self?.sendNotification(title: "App Blocked", body: "\(appName) is not available right now.")
                } else {
                    self?.logger.error("Failed to kill \(appName): \(error ?? "unknown")")
                }
            }
        }
    }

    func appMonitor(_ monitor: AppMonitor, checkScheduledApp bundleId: String, pid: Int32, appName: String, allowedScheduleId: UUID?) {
        guard !currentPolicy.isScheduledAppAllowed(scheduleId: allowedScheduleId) else { return }
        logger.info("App outside schedule: \(appName) (\(bundleId))")
        appMonitor(monitor, didDetectBlockedApp: bundleId, pid: pid, appName: appName)
    }

    func appMonitor(_ monitor: AppMonitor, didActivateApp bundleId: String?, appName: String?) {
        usageTracker.appDidActivate(bundleId: bundleId, appName: appName)
    }

    func appMonitor(_ monitor: AppMonitor, didLaunchApp bundleId: String, appName: String) {
        usageTracker.appDidLaunch(bundleId: bundleId, appName: appName)
    }

    func appMonitor(_ monitor: AppMonitor, didTerminateApp bundleId: String, appName: String) {
        usageTracker.appDidTerminate(bundleId: bundleId, appName: appName)
    }

    // MARK: - Notifications
    // NOTE: UNUserNotificationCenter requires an .app bundle proxy and cannot be used
    // in a LaunchAgent CLI tool. Blocked-app events are logged here; user-facing
    // notifications will be delivered by PaCo.app in V1.1 via Bonjour.

    private func sendNotification(title: String, body: String) {
        logger.info("Notification (not delivered — agent has no bundle): \(title): \(body)")
    }

    func requestNotificationPermission() {
        // No-op in agent context; handled by PaCo.app
    }
}
