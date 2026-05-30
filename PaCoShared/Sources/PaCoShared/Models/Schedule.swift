import Foundation
import SwiftData

@Model
public final class Schedule: Schedulable {
    @Attribute(.unique) public var id: UUID
    public var label: String
    public var daysRaw: [Int]
    public var offHour: Int
    public var offMinute: Int
    public var onHour: Int
    public var onMinute: Int
    public var gracePeriodMinutes: Int
    public var isActive: Bool

    public var childProfile: ChildProfile?

    public var days: [DayOfWeek] {
        get { daysRaw.compactMap { DayOfWeek(rawValue: $0) } }
        set { daysRaw = newValue.map(\.rawValue) }
    }

    public var internetOffAt: DateComponents {
        DateComponents(hour: offHour, minute: offMinute)
    }

    public var internetOnAt: DateComponents {
        DateComponents(hour: onHour, minute: onMinute)
    }

    public init(
        label: String,
        days: [DayOfWeek],
        offHour: Int,
        offMinute: Int,
        onHour: Int,
        onMinute: Int,
        gracePeriodMinutes: Int = 5,
        isActive: Bool = true
    ) {
        self.id = UUID()
        self.label = label
        self.daysRaw = days.map(\.rawValue)
        self.offHour = offHour
        self.offMinute = offMinute
        self.onHour = onHour
        self.onMinute = onMinute
        self.gracePeriodMinutes = gracePeriodMinutes
        self.isActive = isActive
    }
}
