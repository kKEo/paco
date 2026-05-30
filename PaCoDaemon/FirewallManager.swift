import Foundation
import PaCoShared

final class FirewallManager {
    private var _isBlocking = false
    private let lock = NSLock()
    private let logger = PaCoLogger.firewall

    var isBlocking: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isBlocking
    }

    func disableInternet() throws {
        lock.lock()
        defer { lock.unlock() }
        let rules = FirewallRuleBuilder.blockInternetRules()
        try rules.write(toFile: FirewallRuleBuilder.anchorFilePath, atomically: true, encoding: .utf8)
        try runPfctl(["-e"])
        try ensureAnchorInMainRuleset()
        try runPfctl(["-a", FirewallRuleBuilder.anchorName, "-f", FirewallRuleBuilder.anchorFilePath])
        _isBlocking = true
        logger.info("Internet disabled: pf anchor rules loaded")
    }

    func enableInternet() throws {
        lock.lock()
        defer { lock.unlock() }
        try runPfctl(["-a", FirewallRuleBuilder.anchorName, "-F", "rules"])
        try? FileManager.default.removeItem(atPath: FirewallRuleBuilder.anchorFilePath)
        _isBlocking = false
        logger.info("Internet enabled: pf anchor rules flushed")
    }

    func verifyIntegrity() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard _isBlocking else { return true }
        do {
            let output = try runPfctlWithOutput(["-a", FirewallRuleBuilder.anchorName, "-sr"])
            let hasBlockRule = output.contains("block drop")
            if !hasBlockRule {
                logger.warning("Tamper detected: pf anchor rules are missing, re-applying...")
                do {
                    try disableInternet()
                    logger.info("Tamper recovery: rules re-applied successfully")
                } catch {
                    logger.error("Tamper recovery FAILED: \(error.localizedDescription)")
                    // State is inconsistent — keep isBlocking true so we keep retrying
                }
            }
            return hasBlockRule
        } catch {
            logger.error("Failed to verify firewall integrity: \(error.localizedDescription)")
            return false
        }
    }

    /// Ensure the pf anchor reference exists in the main ruleset.
    /// Uses /etc/pf.anchors/ for the anchor file and only appends to pf.conf if needed.
    /// Idempotent: multiple calls are safe.
    private func ensureAnchorInMainRuleset() throws {
        let pfConf = "/etc/pf.conf"
        let anchorLine = "anchor \"\(FirewallRuleBuilder.anchorName)\""

        // Read current pf.conf
        let content: String
        do {
            content = try String(contentsOfFile: pfConf, encoding: .utf8)
        } catch {
            logger.warning("Cannot read \(pfConf): \(error.localizedDescription)")
            return
        }

        // Already present — nothing to do
        if content.contains(anchorLine) { return }

        // Create a backup before modifying
        let backupPath = pfConf + ".paco-backup"
        if !FileManager.default.fileExists(atPath: backupPath) {
            try? FileManager.default.copyItem(atPath: pfConf, toPath: backupPath)
            logger.info("Backed up \(pfConf) to \(backupPath)")
        }

        // Append anchor line
        let updatedContent = content.trimmingCharacters(in: .newlines) + "\n\(anchorLine)\n"
        do {
            try updatedContent.write(toFile: pfConf, atomically: true, encoding: .utf8)
            try runPfctl(["-f", pfConf])
            logger.info("Added anchor to \(pfConf)")
        } catch {
            logger.error("Failed to update \(pfConf): \(error.localizedDescription)")
            // Try to restore backup
            if FileManager.default.fileExists(atPath: backupPath) {
                try? FileManager.default.copyItem(atPath: backupPath, toPath: pfConf)
                _ = try? runPfctl(["-f", pfConf])
                logger.info("Restored \(pfConf) from backup")
            }
            throw error
        }
    }

    @discardableResult
    private func runPfctl(_ arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FirewallError.pfctlFailed(arguments: arguments, exitCode: process.terminationStatus)
        }
        return process
    }

    private func runPfctlWithOutput(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum FirewallError: LocalizedError {
    case pfctlFailed(arguments: [String], exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .pfctlFailed(let args, let code):
            return "pfctl \(args.joined(separator: " ")) exited with code \(code)"
        }
    }
}
