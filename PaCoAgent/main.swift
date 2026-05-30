import AppKit
import Foundation
import PaCoShared

let logger = PaCoLogger.agent
logger.info("PaCo Agent starting...")

// Need NSApplication for NSWorkspace notifications
let app = NSApplication.shared
let delegate = AgentDelegate()
delegate.start()

logger.info("PaCo Agent running")

// Run the agent indefinitely
app.run()
