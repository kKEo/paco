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
        let result = ScheduleEvaluator.evaluate(schedules: [], at: Date())
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
