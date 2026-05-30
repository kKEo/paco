import Foundation
import PaCoShared

final class DaemonService: NSObject, DaemonXPCProtocol {
    private let firewallManager = FirewallManager()
    private let processManager = ProcessManager()
    private let logger = PaCoLogger.daemon

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

    func status(reply: @escaping (String) -> Void) {
        let blocking = firewallManager.isBlocking
        reply("daemon running, internet \(blocking ? "blocked" : "allowed")")
    }
}

final class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    private let logger = PaCoLogger.daemon

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: DaemonXPCProtocol.self)
        newConnection.exportedObject = DaemonService()
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.info("XPC connection invalidated")
        }
        newConnection.resume()
        logger.info("Accepted new XPC connection")
        return true
    }
}
