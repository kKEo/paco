import Foundation

/// Codable schedule representation for network transfer and agent-side storage.
/// The agent cannot use SwiftData @Model classes, so this lightweight struct
/// is used for JSON serialization over Bonjour and local file caching.
public struct ScheduleTransfer: Codable, Sendable, Equatable, Schedulable {
    public var id: UUID
    public var label: String
    public var days: [DayOfWeek]
    public var offHour: Int
    public var offMinute: Int
    public var onHour: Int
    public var onMinute: Int
    public var gracePeriodMinutes: Int
    public var isActive: Bool
    /// The child profile this schedule belongs to (nil = applies to every profile).
    public var profileId: UUID?

    public init(
        id: UUID = UUID(),
        label: String,
        days: [DayOfWeek],
        offHour: Int,
        offMinute: Int,
        onHour: Int,
        onMinute: Int,
        gracePeriodMinutes: Int = 5,
        isActive: Bool = true,
        profileId: UUID? = nil
    ) {
        self.id = id
        self.label = label
        self.days = days
        self.offHour = offHour
        self.offMinute = offMinute
        self.onHour = onHour
        self.onMinute = onMinute
        self.gracePeriodMinutes = gracePeriodMinutes
        self.isActive = isActive
        self.profileId = profileId
    }

    /// Convert from a SwiftData Schedule model
    public init(from schedule: Schedule) {
        self.id = schedule.id
        self.label = schedule.label
        self.days = schedule.days
        self.offHour = schedule.offHour
        self.offMinute = schedule.offMinute
        self.onHour = schedule.onHour
        self.onMinute = schedule.onMinute
        self.gracePeriodMinutes = schedule.gracePeriodMinutes
        self.isActive = schedule.isActive
        self.profileId = schedule.childProfile?.id
    }
}
