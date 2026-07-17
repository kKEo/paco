import Foundation
import SystemConfiguration
import PaCoShared

final class DaemonService: NSObject, DaemonXPCProtocol {
    static let shared = DaemonService()

    private let firewallManager = FirewallManager()
    private let processManager = ProcessManager()
    private let logger = PaCoLogger.daemon
    private var integrityTimer: DispatchSourceTimer?
    private let integrityQueue = DispatchQueue(label: "com.paco.daemon.integrity")

    private override init() {
        super.init()
    }

    func enableInternet(reply: @escaping (Bool, String?) -> Void) {
        do {
            try firewallManager.enableInternet()
            reply(true, nil)
        } catch {
            logger.error("enableInternet failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func disableInternet(reply: @escaping (Bool, String?) -> Void) {
        do {
            try firewallManager.disableInternet()
            reply(true, nil)
        } catch {
            logger.error("disableInternet failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func isInternetEnabled(reply: @escaping (Bool) -> Void) {
        reply(!firewallManager.isBlocking)
    }

    func killProcess(pid: Int32, reply: @escaping (Bool, String?) -> Void) {
        let success = processManager.killProcess(pid: pid)
        reply(success, success ? nil : "Failed to kill process \(pid)")
    }

    func verifyFirewallIntegrity(reply: @escaping (Bool) -> Void) {
        reply(firewallManager.verifyIntegrity())
    }

    func updateRestrictedApps(bundleIDs: [String], reply: @escaping (Bool) -> Void) {
        processManager.updateRestrictedApps(Set(bundleIDs))
        reply(true)
    }

    func status(reply: @escaping (String) -> Void) {
        let blocking = firewallManager.isBlocking
        reply("daemon running, internet \(blocking ? "blocked" : "allowed")")
    }

    /// Called once at launch: reconcile persisted block state and start the
    /// self-driven integrity check so tamper detection runs without the app open.
    func startup() {
        firewallManager.reconcileOnStartup()
        let timer = DispatchSource.makeTimerSource(queue: integrityQueue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            _ = self?.firewallManager.verifyIntegrity()
            self?.ensureAgentRunning()
        }
        timer.resume()
        integrityTimer = timer
    }

    /// Best-effort watchdog: re-bootstrap the LaunchAgent into the console user's
    /// GUI domain if the monitored user has unloaded it. `KeepAlive` handles
    /// crashes; this counters a deliberate `launchctl bootout`.
    private func ensureAgentRunning() {
        var uid: uid_t = 0
        let store = SCDynamicStoreCreate(nil, "com.paco.daemon" as CFString, nil, nil)
        let user = SCDynamicStoreCopyConsoleUser(store, &uid, nil)
        guard user != nil, uid != 0 else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootstrap", "gui/\(uid)", "/Library/LaunchAgents/com.paco.agent.plist"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

final class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    private let logger = PaCoLogger.daemon

    /// Developer ID Team Identifier that legitimate PaCo binaries are signed with.
    /// TODO: set to your real 10-char Team ID before shipping a Release build.
    private static let teamIdentifier = "REPLACE_WITH_TEAMID"

    /// Designated requirement the connecting process must satisfy: Apple-issued
    /// Developer ID chain, our team, and a com.paco.* identifier. Pinning the
    /// Team ID (not just the identifier) prevents a self-signed binary that merely
    /// claims a com.paco.* identifier from being accepted.
    private static var designatedRequirement: SecRequirement? = {
        let text = "anchor apple generic "
            + "and identifier \"com.paco.*\" "
            + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(text as CFString, [], &requirement)
        return status == errSecSuccess ? requirement : nil
    }()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let connectingPID = newConnection.processIdentifier
        guard validateConnection(pid: connectingPID) else {
            logger.warning("Rejected XPC connection from PID \(connectingPID): failed validation")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: DaemonXPCProtocol.self)
        newConnection.exportedObject = DaemonService.shared
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.info("XPC connection invalidated")
        }
        newConnection.resume()
        logger.info("Accepted XPC connection from PID \(connectingPID)")
        return true
    }

    /// Validate that the connecting process satisfies our designated requirement
    /// (Apple anchor + our Team ID + com.paco.* identifier).
    private func validateConnection(pid: Int32) -> Bool {
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let code else {
            logger.warning("Cannot obtain SecCode for PID \(pid)")
            return devFallbackAllow()
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return devFallbackAllow()
        }

        guard let requirement = Self.designatedRequirement else {
            logger.error("Designated requirement unavailable; refusing connection")
            return devFallbackAllow()
        }

        let status = SecStaticCodeCheckValidity(staticCode, [], requirement)
        if status != errSecSuccess {
            logger.warning("Connection from PID \(pid) failed designated requirement (status \(status))")
            return false
        }
        return true
    }

    /// In DEBUG builds only, and only when explicitly opted in via the
    /// `PACO_ALLOW_UNSIGNED_XPC` environment variable, allow unsigned callers so
    /// local development works. Never compiled into Release.
    private func devFallbackAllow() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PACO_ALLOW_UNSIGNED_XPC"] == "1" {
            logger.warning("DEBUG: allowing unsigned XPC caller (PACO_ALLOW_UNSIGNED_XPC=1)")
            return true
        }
        #endif
        return false
    }
}
