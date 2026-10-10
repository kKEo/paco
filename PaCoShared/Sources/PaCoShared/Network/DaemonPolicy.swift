import Foundation

/// The enforcement policy as held by the root daemon: the parent's schedules and
/// app restrictions, the device's active child profile, and any approved
/// time-extension override. The daemon evaluates it itself every tick and
/// persists it under `/Library/Application Support/PaCo/`, which the monitored
/// user cannot write. The agent only *reads* it (over XPC) to know which apps to
/// watch and report.
public struct DaemonPolicy: Codable, Sendable, Equatable {
    public var schedules: [ScheduleTransfer]
    public var restrictions: [AppRestrictionTransfer]
    public var activeProfileId: UUID?
    /// Approved time extension.
    public var override: InternetOverride?
    /// Parent's manual toggle; checked before schedules and the extension override.
    public var manualOverride: ManualInternetOverride?
    public var updatedAt: Date

    public static let empty = DaemonPolicy(schedules: [], restrictions: [], activeProfileId: nil, override: nil, updatedAt: .distantPast)

    public init(
        schedules: [ScheduleTransfer],
        restrictions: [AppRestrictionTransfer],
        activeProfileId: UUID? = nil,
        override: InternetOverride? = nil,
        manualOverride: ManualInternetOverride? = nil,
        updatedAt: Date = Date()
    ) {
        self.schedules = schedules
        self.restrictions = restrictions
        self.activeProfileId = activeProfileId
        self.override = override
        self.manualOverride = manualOverride
        self.updatedAt = updatedAt
    }

    /// Replace schedules + restrictions, keeping the device-local profile and the override.
    public mutating func apply(_ transfer: PolicyTransfer, at date: Date = Date()) {
        schedules = transfer.schedules
        restrictions = transfer.restrictions
        updatedAt = date
    }

    /// Restrictions that apply to this device: those of the active profile (plus
    /// any without a profile), or all of them when no profile is selected.
    public var activeRestrictions: [AppRestrictionTransfer] {
        guard let pid = activeProfileId else { return restrictions }
        return restrictions.filter { $0.profileId == nil || $0.profileId == pid }
    }

    /// Schedules that apply to this device, by the same rule as `activeRestrictions`.
    public var activeSchedules: [ScheduleTransfer] {
        guard let pid = activeProfileId else { return schedules }
        return schedules.filter { $0.profileId == nil || $0.profileId == pid }
    }

    /// The manual override if it is still in effect at `date`.
    public func activeManualOverride(at date: Date = Date()) -> ManualInternetOverride? {
        guard let manualOverride, manualOverride.isActive(at: date) else { return nil }
        return manualOverride
    }

    /// Bundle identifiers the daemon may kill.
    public var restrictedBundleIDs: Set<String> {
        Set(activeRestrictions.map(\.bundleIdentifier))
    }

    /// The override expiry if it is still in the future at `date`.
    public func activeOverrideUntil(at date: Date = Date()) -> Date? {
        guard let override, override.isActive(at: date) else { return nil }
        return override.grantedUntil
    }

    /// What the internet should be doing at `date`. Precedence: an active manual
    /// toggle, then an approved extension, then the most restrictive active schedule.
    public func internetAction(at date: Date = Date()) -> InternetAction {
        if let manual = activeManualOverride(at: date) {
            return manual.enabled ? .allowed : .blocked
        }
        return ScheduleEvaluator.evaluate(schedules: activeSchedules, at: date, overrideUntil: activeOverrideUntil(at: date))
    }

    /// Whether a "follows schedule" app may run at `date`: it is blocked exactly
    /// while its schedule blocks the internet (an approved extension lifts it too).
    /// A disabled schedule blocks nothing, like it does for the internet. A missing
    /// schedule id (deleted schedule) keeps the app blocked so a stale rule is
    /// never silently lenient; the dashboard flags such rules.
    public func isScheduledAppAllowed(scheduleId: UUID?, at date: Date = Date()) -> Bool {
        guard let scheduleId, let schedule = schedules.first(where: { $0.id == scheduleId }) else { return false }
        guard schedule.isActive else { return true }
        return ScheduleEvaluator.evaluate(schedules: [schedule], at: date, overrideUntil: activeOverrideUntil(at: date)) == .allowed
    }
}
