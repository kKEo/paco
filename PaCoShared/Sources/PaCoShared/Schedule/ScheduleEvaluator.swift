import Foundation

public enum InternetAction: Equatable, Sendable {
    case allowed
    case blocked
    case gracePeriod(remainingSeconds: Int)
}

/// Protocol that both Schedule (@Model) and ScheduleTransfer (Codable) can conform to.
/// Eliminates the need to convert ScheduleTransfer → Schedule in the agent.
public protocol Schedulable {
    var days: [DayOfWeek] { get }
    var offHour: Int { get }
    var offMinute: Int { get }
    var onHour: Int { get }
    var onMinute: Int { get }
    var gracePeriodMinutes: Int { get }
    var isActive: Bool { get }
}

public enum ScheduleEvaluator {

    /// Evaluate all active schedules at a given time.
    /// Most restrictive wins: if any schedule says blocked, result is blocked.
    ///
    /// - Parameter overrideUntil: when non-nil and in the future, a temporary grant
    ///   (an approved time extension) that supersedes schedule blocking.
    public static func evaluate<S: Schedulable>(
        schedules: [S],
        at date: Date,
        overrideUntil: Date? = nil
    ) -> InternetAction {
        // An active override wins over everything: approved extra time.
        if let overrideUntil, overrideUntil > date {
            return .allowed
        }

        let activeSchedules = schedules.filter(\.isActive)
        guard !activeSchedules.isEmpty else { return .allowed }

        var hasGrace: InternetAction?

        for schedule in activeSchedules {
            let action = evaluateSingle(schedule: schedule, at: date)
            switch action {
            case .blocked:
                return .blocked  // Most restrictive wins immediately
            case .gracePeriod:
                hasGrace = action
            case .allowed:
                continue
            }
        }

        return hasGrace ?? .allowed
    }

    /// Evaluate one schedule.
    ///
    /// A window is attributed to the day it *starts* on. For an overnight window
    /// (off > on, e.g. 21:00 → 07:00) the part after midnight belongs to the
    /// previous day's selection: "Thursday 21:00 → 07:00" blocks until Friday
    /// 07:00 and does not block Friday evening. Same-day windows use today only.
    private static func evaluateSingle<S: Schedulable>(schedule: S, at date: Date) -> InternetAction {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let currentMinutes = hour * 60 + minute

        let offMinutes = schedule.offHour * 60 + schedule.offMinute
        let onMinutes = schedule.onHour * 60 + schedule.onMinute
        guard offMinutes != onMinutes else { return .allowed }  // off == on means no block

        let isOvernight = offMinutes > onMinutes
        let isInBlockedWindow: Bool
        let windowStartDay: Date
        if isOvernight {
            if currentMinutes >= offMinutes {
                isInBlockedWindow = true
                windowStartDay = date
            } else if currentMinutes < onMinutes {
                isInBlockedWindow = true
                windowStartDay = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            } else {
                return .allowed
            }
        } else {
            isInBlockedWindow = currentMinutes >= offMinutes && currentMinutes < onMinutes
            windowStartDay = date
        }
        guard isInBlockedWindow else { return .allowed }

        guard let day = DayOfWeek.from(weekday: calendar.component(.weekday, from: windowStartDay)),
              schedule.days.contains(day) else {
            return .allowed
        }

        // Grace period: only right after offMinutes, possibly wrapping past midnight.
        if schedule.gracePeriodMinutes > 0 {
            let graceEndMinutes = offMinutes + schedule.gracePeriodMinutes
            if graceEndMinutes > 24 * 60 {
                let wrappedEnd = graceEndMinutes - 24 * 60
                if currentMinutes >= offMinutes {
                    return .gracePeriod(remainingSeconds: ((24 * 60 - currentMinutes) + wrappedEnd) * 60)
                } else if currentMinutes < wrappedEnd {
                    return .gracePeriod(remainingSeconds: (wrappedEnd - currentMinutes) * 60)
                }
            } else if currentMinutes >= offMinutes && currentMinutes < graceEndMinutes {
                return .gracePeriod(remainingSeconds: (graceEndMinutes - currentMinutes) * 60)
            }
        }

        return .blocked
    }
}
