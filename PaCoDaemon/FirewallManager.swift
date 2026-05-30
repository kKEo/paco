import Foundation
import PaCoShared

final class FirewallManager {
    private(set) var isBlocking = false
    private let logger = PaCoLogger.firewall

    func disableInternet() throws {
        let rules = FirewallRuleBuilder.blockInternetRules()
        try rules.write(toFile: FirewallRuleBuilder.anchorFilePath, atomically: true, encoding: .utf8)
        try runPfctl(["-e"])
        try ensureAnchorInMainRuleset()
        try runPfctl(["-a", FirewallRuleBuilder.anchorName, "-f", FirewallRuleBuilder.anchorFilePath])
        isBlocking = true
        logger.info("Internet disabled: pf anchor rules loaded")
    }

    func enableInternet() throws {
        try runPfctl(["-a", FirewallRuleBuilder.anchorName, "-F", "rules"])
        try? FileManager.default.removeItem(atPath: FirewallRuleBuilder.anchorFilePath)
        isBlocking = false
        logger.info("Internet enabled: pf anchor rules flushed")
    }

    func verifyIntegrity() -> Bool {
        guard isBlocking else { return true }
        do {
            let output = try runPfctlWithOutput(["-a", FirewallRuleBuilder.anchorName, "-sr"])
            let hasBlockRule = output.contains("block drop")
            if !hasBlockRule {
                logger.warning("Tamper detected: pf anchor rules are missing")
                try? disableInternet()
            }
            return hasBlockRule
        } catch {
            logger.error("Failed to verify firewall integrity: \(error.localizedDescription)")
            return false
        }
    }

    private func ensureAnchorInMainRuleset() throws {
        let pfConf = "/etc/pf.conf"
        let anchorLine = "anchor \"\(FirewallRuleBuilder.anchorName)\""
        guard let content = try? String(contentsOfFile: pfConf, encoding: .utf8) else { return }
        if content.contains(anchorLine) { return }
        let updatedContent = content + "\n\(anchorLine)\n"
        try updatedContent.write(toFile: pfConf, atomically: true, encoding: .utf8)
        try runPfctl(["-f", pfConf])
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
