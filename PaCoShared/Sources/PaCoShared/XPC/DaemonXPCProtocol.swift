import Foundation

/// The root daemon's XPC interface. The daemon owns the enforcement policy and
/// evaluates it itself; callers push policy in and read status out.
@objc public protocol DaemonXPCProtocol {
    /// Parent's manual toggle: force internet on/off for `minutes`, after which the
    /// schedule takes over again. Replaces the old untimed enable/disable.
    func setManualInternet(enabled: Bool, minutes: Int, reply: @escaping (Bool, String?) -> Void)
    /// Drop the manual toggle and return to the schedule immediately.
    func clearManualInternet(reply: @escaping (Bool, String?) -> Void)
    func isInternetEnabled(reply: @escaping (Bool) -> Void)
    func killProcess(pid: Int32, reply: @escaping (Bool, String?) -> Void)
    func verifyFirewallIntegrity(reply: @escaping (Bool) -> Void)
    func status(reply: @escaping (String) -> Void)

    /// Replace schedules + app restrictions with a JSON-encoded `PolicyTransfer`.
    /// The daemon persists it, re-derives its kill allowlist and re-evaluates at once.
    func updatePolicy(_ policyData: Data, reply: @escaping (Bool, String?) -> Void)
    /// Select which child profile's restrictions apply on this device (nil = all).
    func setActiveProfile(_ profileId: String?, reply: @escaping (Bool, String?) -> Void)
    /// Grant a temporary internet window (an approved time extension).
    func grantInternetOverride(requestId: String, until: Date, reply: @escaping (Bool, String?) -> Void)
    /// The daemon's current policy as JSON-encoded `DaemonPolicy` (nil on encoding failure).
    func fetchPolicy(reply: @escaping (Data?) -> Void)
}
