import Foundation
import PaCoShared

/// XPC client used by the main app to communicate with the daemon.
/// Used in parent mode when running on the same machine as the child.
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

    private var proxy: DaemonXPCProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.logger.error("XPC error: \(error.localizedDescription)")
        } as? DaemonXPCProtocol
    }
}
