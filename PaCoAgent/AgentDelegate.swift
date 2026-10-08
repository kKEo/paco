// PaCoAgent/AgentDelegate.swift
import Foundation
import PaCoShared

final class AgentDelegate: NSObject, AppMonitorDelegate {

    private let appMonitor = AppMonitor()
    private let usageTracker = UsageTracker()
    private var scheduleTimer: DispatchSourceTimer?
    private var daemonConnection: NSXPCConnection?
    private let logger = PaCoLogger.agent
    private var currentSchedules: [ScheduleTransfer] = []
    /// Last internet state we asked the daemon for, so we only act on changes (edge-trigger).
    private var lastAppliedInternetEnabled: Bool?
    /// Last restricted-app set pushed to the daemon, to avoid redundant XPC calls.
    private var lastPushedRestrictedApps: Set<String> = []

    func start() {
        appMonitor.delegate = self
        appMonitor.start()
        connectToDaemon()
        startScheduleTimer()
        logger.info("AgentDelegate started")
    }

    // MARK: - Daemon XPC connection

    private func connectToDaemon() {
        let connection = NSXPCConnection(machServiceName: "com.paco.daemon", options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: DaemonXPCProtocol.self)
        connection.interruptionHandler = { [weak self] in
            // Daemon crashed/restarted: its in-memory state (kill allowlist) is gone and
            // the mach connection will transparently reconnect on next use.
            self?.logger.warning("Daemon XPC connection interrupted; will re-sync state")
            DispatchQueue.main.async { self?.forgetDaemonState() }
        }
        connection.invalidationHandler = { [weak self] in
            self?.logger.warning("Daemon XPC connection invalidated, reconnecting...")
            DispatchQueue.main.async { self?.forgetDaemonState() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.connectToDaemon() }
        }
        connection.resume()
        daemonConnection = connection
        logger.info("Connected to daemon via XPC")
    }

    /// Drop the edge-trigger markers so the next tick re-pushes the restricted-app
    /// set and re-asserts the desired internet state to a (re)started daemon.
    private func forgetDaemonState() {
        lastAppliedInternetEnabled = nil
        lastPushedRestrictedApps = []
    }

    private var daemonProxy: DaemonXPCProtocol? {
        daemonConnection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.logger.error("Daemon XPC error: \(error.localizedDescription)")
        } as? DaemonXPCProtocol
    }

    // MARK: - Schedule + restriction timer

    private func startScheduleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 30)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        scheduleTimer = timer
    }

    private func tick() {
        let config = loadConfig()
        let schedules = loadSchedules()
        let restrictions = loadRestrictions(activeProfileId: config?.activeProfileId)
        currentSchedules = schedules
        appMonitor.updateRestrictions(restrictions)
        pushRestrictedApps(restrictions)
        evaluateSchedules(schedules)
        writeUsage(profileId: config?.activeProfileId)
    }

    /// Push the set of bundle IDs the daemon may kill (all restricted apps).
    /// Without this the daemon's kill allowlist stays empty and blocking never works.
    private func pushRestrictedApps(_ restrictions: [AppRestrictionTransfer]) {
        let bundleIDs = Set(restrictions.map(\.bundleIdentifier))
        guard bundleIDs != lastPushedRestrictedApps else { return }
        daemonProxy?.updateRestrictedApps(bundleIDs: Array(bundleIDs)) { [weak self] success in
            DispatchQueue.main.async {
                if success { self?.lastPushedRestrictedApps = bundleIDs }
            }
        }
    }

    private func loadConfig() -> DeviceConfigTransfer? {
        guard let data = try? Data(contentsOf: PaCoFiles.configFileURL),
              let config = try? JSONDecoder().decode(DeviceConfigTransfer.self, from: data)
        else { return nil }
        return config
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
    }

    private func loadSchedules() -> [ScheduleTransfer] {
        guard let data = try? Data(contentsOf: PaCoFiles.schedulesFileURL),
              let schedules = try? JSONDecoder().decode([ScheduleTransfer].self, from: data)
        else { return [] }
        return schedules
    }

    private func loadRestrictions(activeProfileId: UUID?) -> [AppRestrictionTransfer] {
        guard let data = try? Data(contentsOf: PaCoFiles.restrictionsFileURL),
              let all = try? JSONDecoder().decode([AppRestrictionTransfer].self, from: data)
        else { return [] }

        // If no active profile configured, enforce all restrictions
        guard let pid = activeProfileId else { return all }
        return all.filter { $0.profileId == pid }
    }

    private func evaluateSchedules(_ schedules: [ScheduleTransfer]) {
        let overrideUntil = OverrideStore.activeUntil()
        let action = ScheduleEvaluator.evaluate(schedules: schedules, at: Date(), overrideUntil: overrideUntil)
        switch action {
        case .allowed:
            applyInternet(enabled: true)
        case .blocked:
            applyInternet(enabled: false)
        case .gracePeriod(let remaining):
            logger.info("Grace period: \(remaining)s remaining")
        }
    }

    /// Edge-triggered: only call the daemon when the desired state changes,
    /// avoiding a pfctl rewrite every 30-second tick. The marker is set only once
    /// the daemon confirms, so a failed call (daemon not up yet, connection
    /// interrupted) is retried on the next tick instead of being silently lost.
    private func applyInternet(enabled: Bool) {
        guard lastAppliedInternetEnabled != enabled else { return }
        setInternet(enabled: enabled)
    }

    // MARK: - Internet control

    func setInternet(enabled: Bool) {
        let completion: (Bool, String?) -> Void = { [weak self] success, error in
            // XPC replies arrive on an arbitrary queue; all agent state lives on main.
            DispatchQueue.main.async {
                guard let self else { return }
                guard success else {
                    self.logger.error("Failed to \(enabled ? "enable" : "disable") internet: \(error ?? "unknown")")
                    return
                }
                self.lastAppliedInternetEnabled = enabled
                if enabled {
                    self.usageTracker.internetDidEnable()
                    self.appendEvent(NotificationEvent(kind: .internetEnabled))
                    self.logger.info("Internet enabled via daemon")
                } else {
                    self.usageTracker.internetDidDisable()
                    self.appendEvent(NotificationEvent(kind: .internetDisabled))
                    self.logger.info("Internet disabled via daemon")
                }
            }
        }
        if enabled {
            daemonProxy?.enableInternet(reply: completion)
        } else {
            daemonProxy?.disableInternet(reply: completion)
        }
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
        guard let scheduleId = allowedScheduleId,
              let schedule = currentSchedules.first(where: { $0.id == scheduleId })
        else {
            // No schedule configured — block it
            appMonitor(monitor, didDetectBlockedApp: bundleId, pid: pid, appName: appName)
            return
        }
        let action = ScheduleEvaluator.evaluate(schedules: [schedule], at: Date(), overrideUntil: OverrideStore.activeUntil())
        if action != .allowed {
            logger.info("App outside schedule: \(appName) (\(bundleId))")
            appMonitor(monitor, didDetectBlockedApp: bundleId, pid: pid, appName: appName)
        }
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
