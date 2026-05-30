import Foundation
import PaCoShared

final class DaemonService: NSObject, DaemonXPCProtocol {
    static let shared = DaemonService()

    private let firewallManager = FirewallManager()
    private let processManager = ProcessManager()
    private let logger = PaCoLogger.daemon

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

    func status(reply: @escaping (String) -> Void) {
        let blocking = firewallManager.isBlocking
        reply("daemon running, internet \(blocking ? "blocked" : "allowed")")
    }
}

final class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    private let logger = PaCoLogger.daemon

    /// Allowed signing identifiers for XPC connections.
    /// In production, replace with your Developer ID team identifier.
    private let allowedSigningTeam = "com.paco"

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Validate the connecting process
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

    /// Validate that the connecting process is signed by us.
    /// Uses SecCode to verify the code signature of the calling process.
    private func validateConnection(pid: Int32) -> Bool {
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        let status = SecCodeCopyGuestWithAttributes(nil, attrs, [], &code)

        guard status == errSecSuccess, let code else {
            logger.warning("Cannot obtain SecCode for PID \(pid)")
            // Allow in development (unsigned builds); deny in production
            #if DEBUG
            return true
            #else
            return false
            #endif
        }

        // Verify code signature is valid
        let verifyStatus = SecCodeCheckValidity(code, [], nil)
        guard verifyStatus == errSecSuccess else {
            logger.warning("Invalid code signature for PID \(pid)")
            return false
        }

        // Convert to static code for signing information
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }

        // Check that the signing identifier starts with our prefix
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, [], &info)
        guard infoStatus == errSecSuccess, let signingInfo = info as? [String: Any],
              let identifier = signingInfo[kSecCodeInfoIdentifier as String] as? String else {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }

        let isAllowed = identifier.hasPrefix(allowedSigningTeam)
        if !isAllowed {
            logger.warning("Rejected connection from '\(identifier)' (not in allowed signers)")
        }
        return isAllowed
    }
}
