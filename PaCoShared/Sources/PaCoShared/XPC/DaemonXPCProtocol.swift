import Foundation

@objc public protocol DaemonXPCProtocol {
    func enableInternet(reply: @escaping (Bool, String?) -> Void)
    func disableInternet(reply: @escaping (Bool, String?) -> Void)
    func isInternetEnabled(reply: @escaping (Bool) -> Void)
    func killProcess(pid: Int32, reply: @escaping (Bool, String?) -> Void)
    func verifyFirewallIntegrity(reply: @escaping (Bool) -> Void)
    func status(reply: @escaping (String) -> Void)
    /// Push the set of bundle IDs the daemon is permitted to kill (blocked/scheduled apps).
    func updateRestrictedApps(bundleIDs: [String], reply: @escaping (Bool) -> Void)
}
