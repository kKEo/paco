import XCTest
@testable import PaCoShared

final class DaemonPolicyTests: XCTestCase {

    private func schedule(id: UUID = UUID(), days: [DayOfWeek] = DayOfWeek.allCases, off: Int, on: Int) -> ScheduleTransfer {
        ScheduleTransfer(id: id, label: "s", days: days, offHour: off, offMinute: 0, onHour: on, onMinute: 0, gracePeriodMinutes: 0)
    }

    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: Date())!
    }

    private func restriction(_ bundle: String, profile: UUID?, type: RestrictionType = .blocked, scheduleId: UUID? = nil) -> AppRestrictionTransfer {
        AppRestrictionTransfer(bundleIdentifier: bundle, appName: bundle, restrictionType: type,
                               allowedScheduleId: scheduleId, profileId: profile)
    }

    func testEmptyPolicyAllowsEverything() {
        XCTAssertEqual(DaemonPolicy.empty.internetAction(), .allowed)
        XCTAssertTrue(DaemonPolicy.empty.restrictedBundleIDs.isEmpty)
    }

    func testActiveProfileFiltersRestrictions() {
        let a = UUID(), b = UUID()
        var policy = DaemonPolicy(schedules: [], restrictions: [
            restriction("com.a", profile: a), restriction("com.b", profile: b), restriction("com.none", profile: nil),
        ])
        XCTAssertEqual(policy.restrictedBundleIDs, ["com.a", "com.b", "com.none"])
        policy.activeProfileId = a
        XCTAssertEqual(policy.restrictedBundleIDs, ["com.a"])
    }

    func testApplyKeepsProfileAndOverride() {
        let profile = UUID()
        let override = InternetOverride(requestId: UUID(), grantedUntil: .distantFuture)
        var policy = DaemonPolicy(schedules: [], restrictions: [], activeProfileId: profile, override: override)
        policy.apply(PolicyTransfer(schedules: [schedule(off: 9, on: 17)],
                                    restrictions: [restriction("com.x", profile: profile), restriction("com.other", profile: UUID())]))
        XCTAssertEqual(policy.activeProfileId, profile)
        XCTAssertEqual(policy.override, override)
        XCTAssertEqual(policy.schedules.count, 1)
        XCTAssertEqual(policy.restrictedBundleIDs, ["com.x"])
    }

    func testScheduleBlocksAndOverrideWins() {
        var policy = DaemonPolicy(schedules: [schedule(off: 9, on: 17)], restrictions: [])
        XCTAssertEqual(policy.internetAction(at: date(hour: 12)), .blocked)
        XCTAssertEqual(policy.internetAction(at: date(hour: 20)), .allowed)

        policy.override = InternetOverride(requestId: UUID(), grantedUntil: date(hour: 13))
        XCTAssertEqual(policy.internetAction(at: date(hour: 12)), .allowed)
        XCTAssertEqual(policy.internetAction(at: date(hour: 14)), .blocked, "expired override no longer applies")
        XCTAssertNil(policy.activeOverrideUntil(at: date(hour: 14)))
    }

    func testScheduledAppRequiresKnownSchedule() {
        let id = UUID()
        let policy = DaemonPolicy(schedules: [schedule(id: id, off: 9, on: 17)], restrictions: [])
        XCTAssertFalse(policy.isScheduledAppAllowed(scheduleId: nil, at: date(hour: 20)))
        XCTAssertFalse(policy.isScheduledAppAllowed(scheduleId: UUID(), at: date(hour: 20)))
        XCTAssertTrue(policy.isScheduledAppAllowed(scheduleId: id, at: date(hour: 20)))
        XCTAssertFalse(policy.isScheduledAppAllowed(scheduleId: id, at: date(hour: 12)))
    }

    func testRoundTrip() throws {
        let policy = DaemonPolicy(
            schedules: [schedule(off: 21, on: 7)],
            restrictions: [restriction("com.x", profile: UUID())],
            activeProfileId: UUID(),
            override: InternetOverride(requestId: UUID(), grantedUntil: Date(timeIntervalSince1970: 1_900_000_000))
        )
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(DaemonPolicy.self, from: data)
        XCTAssertEqual(decoded.schedules, policy.schedules)
        XCTAssertEqual(decoded.restrictions, policy.restrictions)
        XCTAssertEqual(decoded.activeProfileId, policy.activeProfileId)
        XCTAssertEqual(decoded.override, policy.override)
    }
}
