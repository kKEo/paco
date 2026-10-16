import Foundation
import PaCoShared

/// Owns the enforcement policy inside the root daemon and evaluates it itself.
///
/// Policy used to live in the monitored user's home directory and be evaluated by
/// the user-level agent, which meant the child could edit the schedule file or
/// forge an override. Now the only way in is the XPC interface (which admits only
/// PaCo binaries signed by this daemon's team), the copy on disk is root-owned,
/// and the internet decision is made here, every tick.
final class PolicyEngine {

    static let policyFilePath = "/Library/Application Support/PaCo/policy.json"
    private static let tickInterval: TimeInterval = 30

    private let firewall: FirewallManager
    private let processManager: ProcessManager
    private let logger = PaCoLogger.daemon
    private let queue = DispatchQueue(label: "com.paco.daemon.policy")
    private var timer: DispatchSourceTimer?

    private let lock = NSLock()
    private var _policy: DaemonPolicy = .empty
    /// Last internet state this engine asked the firewall for; the firewall is only
    /// touched when the desired state changes. Manual toggles are part of the
    /// policy (`manualOverride`), so every tick is a pure function of policy + time.
    private var lastAppliedEnabled: Bool?

    init(firewall: FirewallManager, processManager: ProcessManager) {
        self.firewall = firewall
        self.processManager = processManager
        _policy = Self.load()
        processManager.updateRestrictedApps(_policy.restrictedBundleIDs)
        logger.info("Policy loaded: \(self._policy.schedules.count) schedules, \(self._policy.restrictions.count) restrictions")
    }

    var policy: DaemonPolicy {
        lock.lock(); defer { lock.unlock() }
        return _policy
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: Self.tickInterval)
        timer.setEventHandler { [weak self] in self?.evaluate() }
        timer.resume()
        self.timer = timer
    }

    // MARK: - Mutations (XPC)

    func update(_ transfer: PolicyTransfer) throws {
        try mutate { $0.apply(transfer) }
        logger.info("Policy updated: \(transfer.schedules.count) schedules, \(transfer.restrictions.count) restrictions")
    }

    func setActiveProfile(_ id: UUID?) throws {
        try mutate { $0.activeProfileId = id }
        logger.info("Active profile set to \(id?.uuidString ?? "none")")
    }

    func grantOverride(requestId: UUID, until: Date) throws {
        guard until > Date() else { throw PolicyError.invalidOverride }
        try mutate {
            $0.override = InternetOverride(requestId: requestId, grantedUntil: until)
            // An approval is the parent's latest word; a standing manual "off" would
            // otherwise silently defeat it.
            if $0.manualOverride?.enabled == false { $0.manualOverride = nil }
        }
        logger.info("Internet override granted until \(until)")
    }

    func setManual(enabled: Bool, minutes: Int) throws {
        guard minutes > 0 else { throw PolicyError.invalidOverride }
        try setManual(enabled: enabled, until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// Manual toggle with an absolute end (PaCo Cloud sends `until`, so a
    /// re-delivered command never extends the window).
    func setManual(enabled: Bool, until: Date) throws {
        guard until > Date() else { throw PolicyError.invalidOverride }
        try mutate { $0.manualOverride = ManualInternetOverride(enabled: enabled, until: until) }
        logger.info("Manual internet \(enabled ? "ON" : "OFF") until \(until)")
    }

    func clearManual() throws {
        try mutate { $0.manualOverride = nil }
        logger.info("Manual internet override cleared")
    }

    private func mutate(_ change: (inout DaemonPolicy) -> Void) throws {
        lock.lock()
        var updated = _policy
        change(&updated)
        updated.updatedAt = Date()
        do {
            try Self.persist(updated)
        } catch {
            lock.unlock()
            throw error
        }
        _policy = updated
        lock.unlock()
        processManager.updateRestrictedApps(updated.restrictedBundleIDs)
        queue.async { [weak self] in self?.evaluate() }
    }

    // MARK: - Evaluation

    private func evaluate() {
        let current = policy
        switch current.internetAction() {
        case .allowed:
            apply(enabled: true)
        case .blocked:
            apply(enabled: false)
        case .gracePeriod(let remaining):
            logger.info("Grace period: \(remaining)s remaining")
        }
    }

    private func apply(enabled: Bool) {
        lock.lock()
        let changed = lastAppliedEnabled != enabled
        lock.unlock()
        guard changed else { return }
        do {
            if enabled { try firewall.enableInternet() } else { try firewall.disableInternet() }
            lock.lock(); lastAppliedEnabled = enabled; lock.unlock()
            logger.info("Schedule: internet \(enabled ? "enabled" : "disabled")")
        } catch {
            logger.error("Schedule: failed to \(enabled ? "enable" : "disable") internet: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence (root-owned)

    private static func load() -> DaemonPolicy {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: policyFilePath)),
              let policy = try? JSONDecoder().decode(DaemonPolicy.self, from: data) else {
            return .empty
        }
        return policy
    }

    private static func persist(_ policy: DaemonPolicy) throws {
        let url = URL(fileURLWithPath: policyFilePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(policy)
        try data.write(to: url, options: .atomic)
        // Readable by the agent (and anyone), writable only by root.
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: policyFilePath)
    }
}

enum PolicyError: LocalizedError {
    case invalidPayload
    case invalidOverride

    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "policy payload could not be decoded"
        case .invalidOverride: return "override expiry must be in the future"
        }
    }
}
