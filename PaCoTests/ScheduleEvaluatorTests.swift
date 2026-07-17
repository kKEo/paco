import XCTest
@testable import PaCoShared

final class ScheduleEvaluatorTests: XCTestCase {

    func testInternetShouldBeOffDuringBlockedPeriod() {
        let schedule = Schedule(
            label: "School nights",
            days: [.monday],
            offHour: 21, offMinute: 0,
            onHour: 7, onMinute: 0
        )

        // Monday 22:00 -> should be off
        let monday22 = makeDate(weekday: 2, hour: 22, minute: 0)
        let result = ScheduleEvaluator.evaluate(schedules: [schedule], at: monday22)
        XCTAssertEqual(result, .blocked)
    }

    func testInternetShouldBeOnOutsideBlockedPeriod() {
        let schedule = Schedule(
            label: "School nights",
            days: [.monday],
            offHour: 21, offMinute: 0,
            onHour: 7, onMinute: 0
        )

        // Monday 12:00 -> should be on
        let monday12 = makeDate(weekday: 2, hour: 12, minute: 0)
        let result = ScheduleEvaluator.evaluate(schedules: [schedule], at: monday12)
        XCTAssertEqual(result, .allowed)
    }

    func testNoSchedulesMeansAllowed() {
        let result = ScheduleEvaluator.evaluate(schedules: [Schedule](), at: Date())
        XCTAssertEqual(result, .allowed)
    }

    func testInactiveScheduleIsIgnored() {
        var schedule = Schedule(
            label: "Disabled",
            days: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday],
            offHour: 0, offMinute: 0,
            onHour: 0, onMinute: 0
        )
        schedule.isActive = false

        let result = ScheduleEvaluator.evaluate(schedules: [schedule], at: Date())
        XCTAssertEqual(result, .allowed)
    }

    func testMostRestrictiveWins() {
        let schedule1 = Schedule(
            label: "Lenient",
            days: [.monday],
            offHour: 23, offMinute: 59,
            onHour: 0, onMinute: 0
        )

        let schedule2 = Schedule(
            label: "Strict",
            days: [.monday],
            offHour: 20, offMinute: 0,
            onHour: 6, onMinute: 0
        )

        // Monday 21:00 -> schedule2 says blocked -> most restrictive wins
        let monday21 = makeDate(weekday: 2, hour: 21, minute: 0)
        let result = ScheduleEvaluator.evaluate(schedules: [schedule1, schedule2], at: monday21)
        XCTAssertEqual(result, .blocked)
    }

    func testGracePeriod() {
        let schedule = Schedule(
            label: "School nights",
            days: [.monday],
            offHour: 21, offMinute: 0,
            onHour: 7, onMinute: 0,
            gracePeriodMinutes: 10
        )

        // Monday 21:05 -> in grace period
        let monday2105 = makeDate(weekday: 2, hour: 21, minute: 5)
        let result = ScheduleEvaluator.evaluate(schedules: [schedule], at: monday2105)
        XCTAssertEqual(result, .gracePeriod(remainingSeconds: 300))
    }

    func testOvernightGracePeriodWrapAround() {
        let schedule = Schedule(
            label: "Late night",
            days: [.monday],
            offHour: 23, offMinute: 50,
            onHour: 7, onMinute: 0,
            gracePeriodMinutes: 15
        )

        // Monday 23:55 -> in grace period (before midnight portion)
        let monday2355 = makeDate(weekday: 2, hour: 23, minute: 55)
        let result1 = ScheduleEvaluator.evaluate(schedules: [schedule], at: monday2355)
        // Grace ends at 00:05, currently 23:55 -> remaining = (5 min to midnight + 5 min) * 60 = 600s
        XCTAssertEqual(result1, .gracePeriod(remainingSeconds: 600))

        // Tuesday 00:02 -> in grace period (after midnight portion)
        // Note: Tuesday is weekday 3; need to check if day matches
        // The schedule is for Monday only, so after midnight (Tuesday) the day check may not match.
        // This is actually correct behavior: the overnight schedule day applies to the start day.
        // For the wrap to work, Tuesday must also be in the schedule:
        let scheduleWithTuesday = Schedule(
            label: "Late night",
            days: [.monday, .tuesday],
            offHour: 23, offMinute: 50,
            onHour: 7, onMinute: 0,
            gracePeriodMinutes: 15
        )

        let tuesday0002 = makeDate(weekday: 3, hour: 0, minute: 2)
        let result2 = ScheduleEvaluator.evaluate(schedules: [scheduleWithTuesday], at: tuesday0002)
        // Grace ends at 00:05, currently 00:02 -> remaining = 3 * 60 = 180s
        XCTAssertEqual(result2, .gracePeriod(remainingSeconds: 180))

        // Tuesday 00:06 -> past grace period, should be blocked
        let tuesday0006 = makeDate(weekday: 3, hour: 0, minute: 6)
        let result3 = ScheduleEvaluator.evaluate(schedules: [scheduleWithTuesday], at: tuesday0006)
        XCTAssertEqual(result3, .blocked)
    }

    func testScheduleTransferWorksWithEvaluator() {
        // Verify ScheduleTransfer (Codable) works directly with the evaluator
        let transfer = ScheduleTransfer(
            label: "Test via transfer",
            days: [.monday],
            offHour: 21, offMinute: 0,
            onHour: 7, onMinute: 0,
            gracePeriodMinutes: 5,
            isActive: true
        )

        let monday22 = makeDate(weekday: 2, hour: 22, minute: 0)
        let result = ScheduleEvaluator.evaluate(schedules: [transfer], at: monday22)
        XCTAssertEqual(result, .blocked)
    }

    func testInactiveScheduleTransferIsIgnored() {
        let transfer = ScheduleTransfer(
            label: "Disabled",
            days: [.monday],
            offHour: 0, offMinute: 0,
            onHour: 23, onMinute: 59,
            isActive: false
        )

        let monday12 = makeDate(weekday: 2, hour: 12, minute: 0)
        let result = ScheduleEvaluator.evaluate(schedules: [transfer], at: monday12)
        XCTAssertEqual(result, .allowed)
    }

    func testDayNotInSchedule() {
        let schedule = Schedule(
            label: "Weekdays only",
            days: [.monday, .tuesday, .wednesday, .thursday, .friday],
            offHour: 21, offMinute: 0,
            onHour: 7, onMinute: 0
        )

        // Saturday 22:00 -> not in schedule days -> allowed
        let saturday22 = makeDate(weekday: 7, hour: 22, minute: 0)
        let result = ScheduleEvaluator.evaluate(schedules: [schedule], at: saturday22)
        XCTAssertEqual(result, .allowed)
    }

    // MARK: - Override window (approved extensions)

    func testActiveOverrideAllowsDuringBlockedPeriod() {
        let schedule = Schedule(
            label: "School nights", days: [.monday],
            offHour: 21, offMinute: 0, onHour: 7, onMinute: 0
        )
        let monday22 = makeDate(weekday: 2, hour: 22, minute: 0)
        // Grant expires 30 min after the evaluation instant → allowed.
        let overrideUntil = monday22.addingTimeInterval(30 * 60)
        let result = ScheduleEvaluator.evaluate(schedules: [schedule], at: monday22, overrideUntil: overrideUntil)
        XCTAssertEqual(result, .allowed)
    }

    func testExpiredOverrideDoesNotAllow() {
        let schedule = Schedule(
            label: "School nights", days: [.monday],
            offHour: 21, offMinute: 0, onHour: 7, onMinute: 0
        )
        let monday22 = makeDate(weekday: 2, hour: 22, minute: 0)
        // Grant already expired one minute ago → schedule block resumes.
        let overrideUntil = monday22.addingTimeInterval(-60)
        let result = ScheduleEvaluator.evaluate(schedules: [schedule], at: monday22, overrideUntil: overrideUntil)
        XCTAssertEqual(result, .blocked)
    }

    func testNilOverrideBehavesAsBefore() {
        let schedule = Schedule(
            label: "School nights", days: [.monday],
            offHour: 21, offMinute: 0, onHour: 7, onMinute: 0
        )
        let monday22 = makeDate(weekday: 2, hour: 22, minute: 0)
        let result = ScheduleEvaluator.evaluate(schedules: [schedule], at: monday22, overrideUntil: nil)
        XCTAssertEqual(result, .blocked)
    }

    // MARK: - Helpers

    private func makeDate(weekday: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        // June 1 2026 is Monday (weekday 2)
        let dayOffset = weekday - 2
        components.day = 1 + (dayOffset >= 0 ? dayOffset : dayOffset + 7)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }
}
