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
        XCTAssertEqual(policy.restrictedBundleIDs, ["com.a", "com.none"], "the active profile's rules plus profile-less ones")
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

    func testActiveProfileFiltersSchedules() {
        let a = UUID(), b = UUID()
        var scheduleA = schedule(off: 9, on: 17); scheduleA.profileId = a
        var scheduleB = schedule(off: 9, on: 17); scheduleB.profileId = b
        var policy = DaemonPolicy(schedules: [scheduleA, scheduleB], restrictions: [])
        XCTAssertEqual(policy.activeSchedules.count, 2, "no active profile: every profile's schedules apply")
        policy.activeProfileId = a
        XCTAssertEqual(policy.activeSchedules.map(\.id), [scheduleA.id])
        policy.activeProfileId = UUID()
        XCTAssertEqual(policy.internetAction(at: date(hour: 12)), .allowed, "another profile's schedule must not block this device")
    }

    func testManualOverrideWinsThenExpires() {
        var policy = DaemonPolicy(schedules: [schedule(off: 9, on: 17)], restrictions: [])
        policy.manualOverride = ManualInternetOverride(enabled: true, until: date(hour: 13))
        XCTAssertEqual(policy.internetAction(at: date(hour: 12)), .allowed, "manual on beats the schedule")
        XCTAssertEqual(policy.internetAction(at: date(hour: 14)), .blocked, "expired manual override falls back to the schedule")

        policy.manualOverride = ManualInternetOverride(enabled: false, until: date(hour: 21))
        policy.override = InternetOverride(requestId: UUID(), grantedUntil: date(hour: 21))
        XCTAssertEqual(policy.internetAction(at: date(hour: 20)), .blocked, "manual off beats an approved extension")
        XCTAssertEqual(policy.internetAction(at: date(hour: 22)), .allowed)
    }

    func testDisabledScheduleDoesNotBlockScheduledApp() {
        let id = UUID()
        var inactive = schedule(id: id, off: 9, on: 17); inactive.isActive = false
        let policy = DaemonPolicy(schedules: [inactive], restrictions: [])
        XCTAssertTrue(policy.isScheduledAppAllowed(scheduleId: id, at: date(hour: 12)))
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
