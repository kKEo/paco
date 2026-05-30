import Foundation
import ServiceManagement
import PaCoShared

final class HelperManager: ObservableObject {

    @Published var isDaemonRegistered = false
    @Published var isAgentRegistered = false

    private let logger = PaCoLogger.app

    func registerHelpers() {
        registerDaemon()
        registerAgent()
    }

    func checkStatus() {
        let daemonService = SMAppService.daemon(plistName: "com.paco.daemon.plist")
        isDaemonRegistered = daemonService.status == .enabled

        let agentService = SMAppService.agent(plistName: "com.paco.agent.plist")
        isAgentRegistered = agentService.status == .enabled

        logger.info("Helper status - daemon: \(self.isDaemonRegistered), agent: \(self.isAgentRegistered)")
    }

    private func registerDaemon() {
        let service = SMAppService.daemon(plistName: "com.paco.daemon.plist")
        do {
            try service.register()
            isDaemonRegistered = true
            logger.info("Daemon registered successfully")
        } catch {
            logger.error("Failed to register daemon: \(error.localizedDescription)")
        }
    }

    private func registerAgent() {
        let service = SMAppService.agent(plistName: "com.paco.agent.plist")
        do {
            try service.register()
            isAgentRegistered = true
            logger.info("Agent registered successfully")
        } catch {
            logger.error("Failed to register agent: \(error.localizedDescription)")
        }
    }

    func unregisterHelpers() {
        do {
            try SMAppService.daemon(plistName: "com.paco.daemon.plist").unregister()
            try SMAppService.agent(plistName: "com.paco.agent.plist").unregister()
            isDaemonRegistered = false
            isAgentRegistered = false
            logger.info("Helpers unregistered")
        } catch {
            logger.error("Failed to unregister helpers: \(error.localizedDescription)")
        }
    }
}
