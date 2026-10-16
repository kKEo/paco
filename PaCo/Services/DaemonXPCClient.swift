import Foundation
import PaCoShared

/// XPC client used by the main app to communicate with the local root daemon,
/// which owns and evaluates the enforcement policy.
final class DaemonXPCClient: ObservableObject {

    @Published var isInternetEnabled = true
    @Published var isConnected = false
    /// The parent's timed manual toggle currently in force, if any.
    @Published var manualOverride: ManualInternetOverride?
    /// The daemon's PaCo Cloud state (nil until first fetched).
    @Published var cloudStatus: CloudStatus?

    /// How long a dashboard toggle overrides the schedule before it takes over again.
    static let manualOverrideMinutes = 60

    private var connection: NSXPCConnection?
    private let logger = PaCoLogger.app

    func connect() {
        let conn = NSXPCConnection(machServiceName: "com.paco.daemon", options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: DaemonXPCProtocol.self)
        conn.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.isConnected = false
            }
            self?.logger.warning("Daemon connection lost")
        }
        conn.resume()
        connection = conn
        isConnected = true
        refreshStatus()
    }

    /// Flip the internet for `manualOverrideMinutes`; the schedule resumes afterwards.
    func toggleInternet() {
        let enable = !isInternetEnabled
        proxy?.setManualInternet(enabled: enable, minutes: Self.manualOverrideMinutes) { [weak self] success, error in
            if !success { self?.logger.error("Manual toggle failed: \(error ?? "unknown")") }
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    /// Drop the manual toggle and let the schedule decide again.
    func clearManualOverride() {
        proxy?.clearManualInternet { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    func refreshStatus() {
        proxy?.isInternetEnabled { [weak self] enabled in
            DispatchQueue.main.async { self?.isInternetEnabled = enabled }
        }
        proxy?.fetchPolicy { [weak self] data in
            let policy = data.flatMap { try? JSONDecoder().decode(DaemonPolicy.self, from: $0) }
            DispatchQueue.main.async { self?.manualOverride = policy?.activeManualOverride() }
        }
        refreshCloudStatus()
    }

    // MARK: - PaCo Cloud

    func refreshCloudStatus() {
        cloud(.status) { _ in }
    }

    /// Run a cloud request in the daemon. The completion runs on main exactly
    /// once, also when the daemon is unreachable; `cloudStatus` is updated from
    /// every reply that carries a status.
    func cloud(_ request: CloudXPCRequest, completion: @escaping (CloudXPCResponse) -> Void) {
        var finished = false
        let finish: (CloudXPCResponse) -> Void = { [weak self] response in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                if let status = response.status { self?.cloudStatus = status }
                completion(response)
            }
        }
        guard let data = try? CloudCodec.encode(request),
              let proxy = connection?.remoteObjectProxyWithErrorHandler({ [weak self] error in
                  self?.logger.error("XPC error: \(error.localizedDescription)")
                  finish(.failure("PaCo's background service is not running."))
              }) as? DaemonXPCProtocol else {
            finish(.failure("PaCo's background service is not running."))
            return
        }
        proxy.cloud(data) { reply in
            let response = reply.flatMap { try? CloudCodec.decode(CloudXPCResponse.self, from: $0) }
            finish(response ?? .failure("PaCo's background service gave an unexpected answer."))
        }
    }

    // MARK: - Policy

    /// Replace the daemon's schedules + app restrictions. Completion runs on main.
    func pushPolicy(_ policy: PolicyTransfer, completion: ((Bool) -> Void)? = nil) {
        guard let data = try? JSONEncoder().encode(policy) else {
            completion?(false)
            return
        }
        guard let proxy else {
            logger.warning("No daemon connection; policy not pushed")
            DispatchQueue.main.async { completion?(false) }
            return
        }
        proxy.updatePolicy(data) { [weak self] success, error in
            if !success { self?.logger.error("Daemon rejected policy: \(error ?? "unknown")") }
            DispatchQueue.main.async { completion?(success) }
        }
    }

    func setActiveProfile(_ id: UUID?) {
        proxy?.setActiveProfile(id?.uuidString) { [weak self] success, error in
            if !success { self?.logger.error("Daemon rejected active profile: \(error ?? "unknown")") }
        }
    }

    /// Grant a temporary internet window (approved time extension). Completion runs on main.
    func grantOverride(requestId: UUID, until: Date, completion: ((Bool) -> Void)? = nil) {
        guard let proxy else {
            DispatchQueue.main.async { completion?(false) }
            return
        }
        proxy.grantInternetOverride(requestId: requestId.uuidString, until: until) { [weak self] success, error in
            if !success { self?.logger.error("Daemon rejected override: \(error ?? "unknown")") }
            DispatchQueue.main.async { completion?(success) }
        }
    }

    private var proxy: DaemonXPCProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.logger.error("XPC error: \(error.localizedDescription)")
        } as? DaemonXPCProtocol
    }
}
