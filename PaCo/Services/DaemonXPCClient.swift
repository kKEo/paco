import Foundation
import PaCoShared

/// XPC client used by the main app to communicate with the local root daemon,
/// which owns and evaluates the enforcement policy.
final class DaemonXPCClient: ObservableObject {

    @Published var isInternetEnabled = true
    @Published var isConnected = false

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

    func toggleInternet() {
        if isInternetEnabled {
            proxy?.disableInternet { [weak self] success, _ in
                if success {
                    DispatchQueue.main.async { self?.isInternetEnabled = false }
                }
            }
        } else {
            proxy?.enableInternet { [weak self] success, _ in
                if success {
                    DispatchQueue.main.async { self?.isInternetEnabled = true }
                }
            }
        }
    }

    func refreshStatus() {
        proxy?.isInternetEnabled { [weak self] enabled in
            DispatchQueue.main.async { self?.isInternetEnabled = enabled }
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
