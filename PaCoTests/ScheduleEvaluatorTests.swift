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
        // Monday-only schedule: the post-midnight part of the window still belongs to Monday.
        let schedule = Schedule(
            label: "Late night",
            days: [.monday],
            offHour: 23, offMinute: 50,
            onHour: 7, onMinute: 0,
            gracePeriodMinutes: 15
        )

        // Monday 23:55 -> grace (before midnight): 5 min to midnight + 5 min = 600s
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [schedule], at: makeDate(weekday: 2, hour: 23, minute: 55)),
                       .gracePeriod(remainingSeconds: 600))
        // Tuesday 00:02 -> grace (after midnight): 3 min = 180s
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [schedule], at: makeDate(weekday: 3, hour: 0, minute: 2)),
                       .gracePeriod(remainingSeconds: 180))
        // Tuesday 00:06 -> past grace, blocked
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [schedule], at: makeDate(weekday: 3, hour: 0, minute: 6)), .blocked)
    }

    // MARK: - Overnight windows belong to the day they start on

    func testOvernightWindowBlocksIntoNextMorning() {
        let thursdayNight = Schedule(label: "Thu night", days: [.thursday], offHour: 21, offMinute: 0, onHour: 7, onMinute: 0, gracePeriodMinutes: 0)
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [thursdayNight], at: makeDate(weekday: 5, hour: 22, minute: 0)), .blocked)
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [thursdayNight], at: makeDate(weekday: 6, hour: 2, minute: 0)), .blocked, "Friday 02:00 is still Thursday's night")
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [thursdayNight], at: makeDate(weekday: 6, hour: 6, minute: 59)), .blocked)
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [thursdayNight], at: makeDate(weekday: 6, hour: 7, minute: 0)), .allowed)
    }

    func testOvernightWindowDoesNotBlockNextEvening() {
        let thursdayNight = Schedule(label: "Thu night", days: [.thursday], offHour: 21, offMinute: 0, onHour: 7, onMinute: 0, gracePeriodMinutes: 0)
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [thursdayNight], at: makeDate(weekday: 6, hour: 22, minute: 0)), .allowed, "Friday night is not selected")
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [thursdayNight], at: makeDate(weekday: 5, hour: 2, minute: 0)), .allowed, "Thursday 02:00 belongs to Wednesday night")
    }

    func testOvernightWindowWrapsFromSundayToMonday() {
        let sundayNight = Schedule(label: "Sun night", days: [.sunday], offHour: 22, offMinute: 0, onHour: 6, onMinute: 0, gracePeriodMinutes: 0)
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [sundayNight], at: makeDate(weekday: 2, hour: 1, minute: 0)), .blocked)
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [sundayNight], at: makeDate(weekday: 2, hour: 23, minute: 0)), .allowed)
    }

    func testSameDayWindowUsesTodayOnly() {
        let schoolHours = Schedule(label: "School", days: [.monday], offHour: 9, offMinute: 0, onHour: 15, onMinute: 0, gracePeriodMinutes: 0)
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [schoolHours], at: makeDate(weekday: 2, hour: 10, minute: 0)), .blocked)
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [schoolHours], at: makeDate(weekday: 2, hour: 16, minute: 0)), .allowed)
        XCTAssertEqual(ScheduleEvaluator.evaluate(schedules: [schoolHours], at: makeDate(weekday: 3, hour: 10, minute: 0)), .allowed)
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
