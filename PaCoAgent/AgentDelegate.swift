import AppKit
import Foundation
import PaCoShared

final class AgentDelegate: NSObject, AppMonitorDelegate {

    private let appMonitor = AppMonitor()
    private let usageTracker = UsageTracker()
    private var scheduleTimer: DispatchSourceTimer?
    private var daemonConnection: NSXPCConnection?
    private let logger = PaCoLogger.agent

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
        connection.invalidationHandler = { [weak self] in
            self?.logger.warning("Daemon XPC connection invalidated, reconnecting...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.connectToDaemon()
            }
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

    // MARK: - Schedule timer

    private func startScheduleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.evaluateSchedules()
        }
        timer.resume()
        scheduleTimer = timer
    }

    private func evaluateSchedules() {
        guard let data = try? Data(contentsOf: schedulesFileURL),
              let schedules = try? JSONDecoder().decode([ScheduleTransfer].self, from: data) else {
            return
        }

        let converted = schedules.map { transfer in
            Schedule(
                label: transfer.label,
                days: transfer.days,
                offHour: transfer.offHour, offMinute: transfer.offMinute,
                onHour: transfer.onHour, onMinute: transfer.onMinute,
                gracePeriodMinutes: transfer.gracePeriodMinutes
            )
        }

        let action = ScheduleEvaluator.evaluate(schedules: converted, at: Date())
        switch action {
        case .allowed:
            setInternet(enabled: true)
        case .blocked:
            setInternet(enabled: false)
        case .gracePeriod(let remaining):
            logger.info("Grace period: \(remaining)s remaining")
            // Internet stays on during grace period
        }
    }

    private var schedulesFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.paco")
            .appendingPathComponent("schedules.json")
    }

    // MARK: - Internet control

    func setInternet(enabled: Bool) {
        if enabled {
            daemonProxy?.enableInternet { [weak self] success, error in
                if success {
                    self?.usageTracker.internetDidEnable()
                    self?.logger.info("Internet enabled via daemon")
                } else {
                    self?.logger.error("Failed to enable internet: \(error ?? "unknown")")
                }
            }
        } else {
            daemonProxy?.disableInternet { [weak self] success, error in
                if success {
                    self?.usageTracker.internetDidDisable()
                    self?.logger.info("Internet disabled via daemon")
                } else {
                    self?.logger.error("Failed to disable internet: \(error ?? "unknown")")
                }
            }
        }
    }

    // MARK: - AppMonitorDelegate

    func appMonitor(_ monitor: AppMonitor, didDetectBlockedApp bundleId: String, pid: Int32, appName: String) {
        daemonProxy?.killProcess(pid: pid) { [weak self] success, error in
            if success {
                self?.logger.info("Killed blocked app: \(appName)")
                self?.sendNotification(title: "App Blocked", body: "\(appName) is not available right now.")
            } else {
                self?.logger.error("Failed to kill \(appName): \(error ?? "unknown")")
            }
        }
    }

    func appMonitor(_ monitor: AppMonitor, didLaunchApp bundleId: String, appName: String) {
        usageTracker.appDidLaunch(bundleId: bundleId, appName: appName)
    }

    func appMonitor(_ monitor: AppMonitor, didTerminateApp bundleId: String, appName: String) {
        usageTracker.appDidTerminate(bundleId: bundleId, appName: appName)
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}
