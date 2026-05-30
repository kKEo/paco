import Foundation
import os

public enum PaCoLogger {
    public static let app = Logger(subsystem: "com.paco", category: "app")
    public static let daemon = Logger(subsystem: "com.paco", category: "daemon")
    public static let agent = Logger(subsystem: "com.paco", category: "agent")
    public static let firewall = Logger(subsystem: "com.paco", category: "firewall")
    public static let network = Logger(subsystem: "com.paco", category: "network")
    public static let security = Logger(subsystem: "com.paco", category: "security")
}
