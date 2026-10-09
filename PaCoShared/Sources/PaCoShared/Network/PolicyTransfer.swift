import Foundation

/// The parent's complete enforcement policy as pushed to a child Mac over
/// Bonjour (`.updatePolicy`). Sent as one message so a schedule-only app rule
/// never arrives before the schedule it references. The child writes both parts
/// to its own `schedules.json` / `restrictions.json`, which its agent enforces.
public struct PolicyTransfer: Codable, Sendable, Equatable {
    public var schedules: [ScheduleTransfer]
    public var restrictions: [AppRestrictionTransfer]

    public init(schedules: [ScheduleTransfer], restrictions: [AppRestrictionTransfer]) {
        self.schedules = schedules
        self.restrictions = restrictions
    }
}
