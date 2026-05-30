import Foundation

public enum InternetAction: Equatable, Sendable {
    case allowed
    case blocked
    case gracePeriod(remainingSeconds: Int)
}

public enum ScheduleEvaluator {

    /// Evaluate all active schedules at a given time.
    /// Most restrictive wins: if any schedule says blocked, result is blocked.
    public static func evaluate(schedules: [Schedule], at date: Date) -> InternetAction {
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

    private static func evaluateSingle(schedule: Schedule, at date: Date) -> InternetAction {
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
        let graceEndMinutes = offMinutes + schedule.gracePeriodMinutes

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
        if schedule.gracePeriodMinutes > 0 && currentMinutes >= offMinutes && currentMinutes < graceEndMinutes {
            let remaining = (graceEndMinutes - currentMinutes) * 60
            return .gracePeriod(remainingSeconds: remaining)
        }

        return .blocked
    }
}
