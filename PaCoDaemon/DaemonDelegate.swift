import Foundation
import Security
import SystemConfiguration
import PaCoShared

final class DaemonService: NSObject, DaemonXPCProtocol {
    static let shared = DaemonService()

    private let firewallManager = FirewallManager()
    private let processManager = ProcessManager()
    private let policyEngine: PolicyEngine
    private let logger = PaCoLogger.daemon
    private var integrityTimer: DispatchSourceTimer?
    private let integrityQueue = DispatchQueue(label: "com.paco.daemon.integrity")

    private override init() {
        policyEngine = PolicyEngine(firewall: firewallManager, processManager: processManager)
        super.init()
    }

    // MARK: - Internet

    func setManualInternet(enabled: Bool, minutes: Int, reply: @escaping (Bool, String?) -> Void) {
        do {
            try policyEngine.setManual(enabled: enabled, minutes: minutes)
            reply(true, nil)
        } catch {
            logger.error("setManualInternet failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func clearManualInternet(reply: @escaping (Bool, String?) -> Void) {
        do {
            try policyEngine.clearManual()
            reply(true, nil)
        } catch {
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

    func status(reply: @escaping (String) -> Void) {
        let blocking = firewallManager.isBlocking
        let policy = policyEngine.policy
        reply("daemon running, internet \(blocking ? "blocked" : "allowed"), \(policy.schedules.count) schedules, \(policy.restrictions.count) restrictions")
    }

    // MARK: - Policy

    func updatePolicy(_ policyData: Data, reply: @escaping (Bool, String?) -> Void) {
        guard let transfer = try? JSONDecoder().decode(PolicyTransfer.self, from: policyData) else {
            reply(false, PolicyError.invalidPayload.localizedDescription)
            return
        }
        do {
            try policyEngine.update(transfer)
            reply(true, nil)
        } catch {
            logger.error("updatePolicy failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func setActiveProfile(_ profileId: String?, reply: @escaping (Bool, String?) -> Void) {
        let id = profileId.flatMap(UUID.init(uuidString:))
        if profileId != nil, id == nil {
            reply(false, "invalid profile id")
            return
        }
        do {
            try policyEngine.setActiveProfile(id)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func grantInternetOverride(requestId: String, until: Date, reply: @escaping (Bool, String?) -> Void) {
        guard let id = UUID(uuidString: requestId) else {
            reply(false, "invalid request id")
            return
        }
        do {
            try policyEngine.grantOverride(requestId: id, until: until)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func fetchPolicy(reply: @escaping (Data?) -> Void) {
        reply(try? JSONEncoder().encode(policyEngine.policy))
    }

    // MARK: - Lifecycle

    /// Called once at launch: reconcile persisted block state, start the policy
    /// tick, and start the self-driven integrity check so tamper detection runs
    /// without the app open.
    func startup() {
        firewallManager.reconcileOnStartup()
        policyEngine.start()
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

/// Accepts XPC connections only from PaCo binaries signed by the same team as
/// this daemon. The requirement is attached to the connection with
/// `setCodeSigningRequirement`, so the system re-checks the peer on every message
/// (no PID lookup, no PID-reuse race) and the team id is read from the daemon's
/// own signature rather than hard-coded.
final class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    private let logger = PaCoLogger.daemon

    /// Bundle identifiers that may talk to the daemon.
    private static let allowedIdentifiers = ["com.paco.app", "com.paco.agent"]

    /// Requirement text, or nil when this daemon is not signed with a team (local
    /// unsigned/ad-hoc builds), in which case no peer can satisfy it.
    private lazy var requirementText: String? = {
        guard let team = Self.ownTeamIdentifier() else { return nil }
        let identifiers = Self.allowedIdentifiers.map { "identifier \"\($0)\"" }.joined(separator: " or ")
        return "anchor apple generic and (\(identifiers)) and certificate leaf[subject.OU] = \"\(team)\""
    }()

    override init() {
        super.init()
        if let text = requirementText {
            logger.info("XPC code-signing requirement: \(text)")
        } else {
            logger.warning("Daemon has no team identifier in its signature; refusing all XPC peers (DEBUG: set PACO_ALLOW_UNSIGNED_XPC=1)")
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let pid = newConnection.processIdentifier
        if let text = requirementText {
            do {
                try newConnection.setCodeSigningRequirement(text)
            } catch {
                logger.error("Invalid code-signing requirement (\(error.localizedDescription)); rejecting PID \(pid)")
                return false
            }
        } else if !devFallbackAllow() {
            logger.warning("Rejected XPC connection from PID \(pid): daemon unsigned and no DEBUG override")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: DaemonXPCProtocol.self)
        newConnection.exportedObject = DaemonService.shared
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.info("XPC connection from PID \(pid) invalidated")
        }
        newConnection.resume()
        logger.info("Accepted XPC connection from PID \(pid)")
        return true
    }

    /// The Team Identifier this daemon binary is signed with, from its own code signature.
    private static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let team = dict[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else { return nil }
        return team
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
