import Foundation
import PaCoShared

let logger = PaCoLogger.daemon
logger.info("PaCo Daemon starting...")

let delegate = DaemonDelegate()
let listener = NSXPCListener(machServiceName: "com.paco.daemon")
listener.delegate = delegate
listener.resume()

logger.info("PaCo Daemon listening on com.paco.daemon")
RunLoop.main.run()
