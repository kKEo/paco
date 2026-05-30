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
    public static func evaluate<S: Schedulable>(schedules: [S], at date: Date) -> InternetAction {
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

    private static func evaluateSingle<S: Schedulable>(schedule: S, at date: Date) -> InternetAction {
        let calendar = Calendar.current

        // Check if today is one of the schedule's active days
        let weekday = calendar.component(.weekday, from: date)
        guard let day = DayOfWeek.from(weekday: weekday),
              schedule.days.contains(day) else {
            return .allowed
        }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let currentMinutes = hour * 60 + minute

        let offMinutes = schedule.offHour * 60 + schedule.offMinute
        let onMinutes = schedule.onHour * 60 + schedule.onMinute

        // Determine if current time is in the blocked window
        let isInBlockedWindow: Bool
        if offMinutes > onMinutes {
            // Overnight block: e.g., 21:00 to 07:00
            isInBlockedWindow = currentMinutes >= offMinutes || currentMinutes < onMinutes
        } else if offMinutes < onMinutes {
            // Same-day block: e.g., 09:00 to 17:00
            isInBlockedWindow = currentMinutes >= offMinutes && currentMinutes < onMinutes
        } else {
            // off == on means no block
            return .allowed
        }

        if !isInBlockedWindow {
            return .allowed
        }

        // Check grace period (only applies right after offMinutes)
        if schedule.gracePeriodMinutes > 0 {
            let graceEndMinutes = offMinutes + schedule.gracePeriodMinutes
            let isInGrace: Bool

            if graceEndMinutes > 24 * 60 {
                // Grace period wraps past midnight:
                // e.g., off at 23:50, grace 15 min → grace until 00:05
                let wrappedEnd = graceEndMinutes - 24 * 60
                isInGrace = currentMinutes >= offMinutes || currentMinutes < wrappedEnd
            } else {
                // Same-day grace period
                isInGrace = currentMinutes >= offMinutes && currentMinutes < graceEndMinutes
            }

            if isInGrace {
                // Calculate remaining seconds
                let remaining: Int
                if graceEndMinutes > 24 * 60 {
                    let wrappedEnd = graceEndMinutes - 24 * 60
                    if currentMinutes >= offMinutes {
                        // Before midnight portion
                        remaining = ((24 * 60 - currentMinutes) + wrappedEnd) * 60
                    } else {
                        // After midnight portion
                        remaining = (wrappedEnd - currentMinutes) * 60
                    }
                } else {
                    remaining = (graceEndMinutes - currentMinutes) * 60
                }
                return .gracePeriod(remainingSeconds: remaining)
            }
        }

        return .blocked
    }
}
