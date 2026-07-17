import Foundation
import Security
import PaCoShared

final class ProcessManager {
    private let logger = PaCoLogger.daemon

    /// Set of bundle IDs that are allowed to be killed.
    /// Updated by the agent (via XPC) when restriction rules change.
    private var _restrictedBundleIDs: Set<String> = []
    private let lock = NSLock()

    private var restrictedBundleIDs: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return _restrictedBundleIDs
    }

    func updateRestrictedApps(_ bundleIDs: Set<String>) {
        lock.lock()
        _restrictedBundleIDs = bundleIDs
        lock.unlock()
        logger.info("Updated restricted apps: \(bundleIDs.count) entries")
    }

    /// Kill a process only if it belongs to a known restricted app.
    /// Returns true if the process was killed, false otherwise.
    func killProcess(pid: Int32, expectedBundleID: String? = nil) -> Bool {
        // Look up the bundle identifier from the process's code signature
        let actualBundleID = bundleIdentifier(for: pid)

        // If we can identify the process, validate it's restricted
        if let actualBundleID {
            if let expected = expectedBundleID, expected != actualBundleID {
                logger.warning("Refused to kill PID \(pid): expected \(expected), found \(actualBundleID)")
                return false
            }

            guard restrictedBundleIDs.contains(actualBundleID) else {
                logger.warning("Refused to kill PID \(pid) (\(actualBundleID)): not in restricted list")
                return false
            }
        } else {
            // Cannot identify the process — refuse to kill unknown processes
            logger.warning("Refused to kill PID \(pid): cannot determine bundle ID")
            return false
        }

        let result = kill(pid, SIGKILL)
        if result == 0 {
            let name = actualBundleID ?? "unknown"
            logger.info("Killed restricted app \(name) (PID \(pid))")
            return true
        } else {
            logger.error("Failed to kill PID \(pid): errno \(errno)")
            return false
        }
    }

    /// Look up the bundle identifier for a process via its code signature.
    /// Works across user sessions (suitable for root daemons).
    private func bundleIdentifier(for pid: Int32) -> String? {
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let code else {
            return nil
        }

        // Convert SecCode to SecStaticCode for signing information
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let signingInfo = info as? [String: Any],
              let identifier = signingInfo[kSecCodeInfoIdentifier as String] as? String else {
            return nil
        }
        return identifier
    }
}
