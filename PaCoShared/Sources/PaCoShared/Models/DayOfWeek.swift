import Foundation

public enum DayOfWeek: Int, Codable, CaseIterable, Identifiable, Sendable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    public var id: Int { rawValue }

    public var shortName: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    public static func from(weekday: Int) -> DayOfWeek? {
        let mapped = weekday == 1 ? 7 : weekday - 1
        return DayOfWeek(rawValue: mapped)
    }
}
