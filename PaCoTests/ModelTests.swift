import XCTest
@testable import PaCoShared

final class ModelTests: XCTestCase {

    func testDayOfWeekFromCalendarWeekday() {
        XCTAssertEqual(DayOfWeek.from(weekday: 2), .monday)
        XCTAssertEqual(DayOfWeek.from(weekday: 1), .sunday)
        XCTAssertEqual(DayOfWeek.from(weekday: 7), .saturday)
        XCTAssertNil(DayOfWeek.from(weekday: 0))
    }

    func testScheduleDaysConversion() {
        let schedule = Schedule(
            label: "Test",
            days: [.monday, .wednesday, .friday],
            offHour: 21, offMinute: 0,
            onHour: 7, onMinute: 0
        )
        XCTAssertEqual(schedule.days, [.monday, .wednesday, .friday])
        XCTAssertEqual(schedule.internetOffAt.hour, 21)
        XCTAssertEqual(schedule.internetOffAt.minute, 0)
        XCTAssertEqual(schedule.internetOnAt.hour, 7)
        XCTAssertEqual(schedule.internetOnAt.minute, 0)
        XCTAssertEqual(schedule.gracePeriodMinutes, 5)
    }

    func testUsageRecordAppUsageRoundTrip() {
        let entries = [
            AppUsageEntry(bundleIdentifier: "com.apple.Safari", appName: "Safari", duration: 3600, launchCount: 5),
            AppUsageEntry(bundleIdentifier: "com.apple.Music", appName: "Music", duration: 1800, launchCount: 2),
        ]
        let record = UsageRecord(date: Date(), internetOnDuration: 7200, appUsage: entries)
        XCTAssertEqual(record.appUsage.count, 2)
        XCTAssertEqual(record.appUsage[0].bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(record.appUsage[1].duration, 1800)
    }

    func testChildProfileInit() {
        let profile = ChildProfile(name: "Alice")
        XCTAssertEqual(profile.name, "Alice")
        XCTAssertNil(profile.avatarImageData)
        XCTAssertNotNil(profile.id)
    }

    func testAppRestrictionInit() {
        let restriction = AppRestriction(
            bundleIdentifier: "com.example.game",
            appName: "Game",
            restrictionType: .blocked
        )
        XCTAssertEqual(restriction.restrictionType, .blocked)
        XCTAssertNil(restriction.allowedScheduleId)
    }

    func testUsageTransferRoundTrip() throws {
        let entry = AppUsageEntry(bundleIdentifier: "com.apple.Safari", appName: "Safari", duration: 120, launchCount: 3)
        let transfer = UsageTransfer(date: Date(timeIntervalSince1970: 1000000), profileId: UUID(), internetOnDuration: 3600, appUsage: [entry])
        let data = try JSONEncoder().encode(transfer)
        let decoded = try JSONDecoder().decode(UsageTransfer.self, from: data)
        XCTAssertEqual(decoded.appUsage.count, 1)
        XCTAssertEqual(decoded.internetOnDuration, 3600)
        XCTAssertEqual(decoded.appUsage[0].bundleIdentifier, "com.apple.Safari")
    }
}
