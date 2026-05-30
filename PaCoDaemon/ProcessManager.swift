import Foundation
import PaCoShared

final class ProcessManager {
    private let logger = PaCoLogger.daemon

    func killProcess(pid: Int32) -> Bool {
        let result = kill(pid, SIGKILL)
        if result == 0 {
            logger.info("Killed process \(pid)")
            return true
        } else {
            logger.error("Failed to kill process \(pid): errno \(errno)")
            return false
        }
    }
}
