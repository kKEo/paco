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
    public var override: InternetOverride?
    public var updatedAt: Date

    public static let empty = DaemonPolicy(schedules: [], restrictions: [], activeProfileId: nil, override: nil, updatedAt: .distantPast)

    public init(
        schedules: [ScheduleTransfer],
        restrictions: [AppRestrictionTransfer],
        activeProfileId: UUID? = nil,
        override: InternetOverride? = nil,
        updatedAt: Date = Date()
    ) {
        self.schedules = schedules
        self.restrictions = restrictions
        self.activeProfileId = activeProfileId
        self.override = override
        self.updatedAt = updatedAt
    }

    /// Replace schedules + restrictions, keeping the device-local profile and the override.
    public mutating func apply(_ transfer: PolicyTransfer, at date: Date = Date()) {
        schedules = transfer.schedules
        restrictions = transfer.restrictions
        updatedAt = date
    }

    /// Restrictions that apply to this device: those of the active profile, or all
    /// of them when no profile is selected.
    public var activeRestrictions: [AppRestrictionTransfer] {
        guard let pid = activeProfileId else { return restrictions }
        return restrictions.filter { $0.profileId == pid }
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

    /// What the internet should be doing at `date`: most restrictive schedule wins,
    /// an active override wins over everything.
    public func internetAction(at date: Date = Date()) -> InternetAction {
        ScheduleEvaluator.evaluate(schedules: schedules, at: date, overrideUntil: activeOverrideUntil(at: date))
    }

    /// Whether a `scheduledOnly` app is allowed to run at `date`. No schedule or an
    /// unknown schedule id means the app is blocked.
    public func isScheduledAppAllowed(scheduleId: UUID?, at date: Date = Date()) -> Bool {
        guard let scheduleId, let schedule = schedules.first(where: { $0.id == scheduleId }) else { return false }
        return ScheduleEvaluator.evaluate(schedules: [schedule], at: date, overrideUntil: activeOverrideUntil(at: date)) == .allowed
    }
}
