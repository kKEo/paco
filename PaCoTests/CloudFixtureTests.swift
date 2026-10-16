import XCTest
@testable import PaCoShared

/// The wire contract with PaCo Cloud. `server/tests/Fixtures/policy.json` is
/// produced by the server's PolicyComposer (its PolicyTest checks it byte for
/// byte); here the Mac side proves it decodes into the same PolicyTransfer.
final class CloudFixtureTests: XCTestCase {
    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("server/tests/Fixtures/policy.json")

    private let profileId = UUID(uuidString: "6f1c2a8e-5b7d-4c3e-9a10-2b3c4d5e6f70")!
    private let schoolNightsId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    private var expected: PolicyTransfer {
        PolicyTransfer(
            schedules: [
                ScheduleTransfer(
                    id: schoolNightsId, label: "School nights",
                    days: [.monday, .tuesday, .wednesday, .thursday, .sunday],
                    offHour: 21, offMinute: 0, onHour: 7, onMinute: 0,
                    gracePeriodMinutes: 5, isActive: true, profileId: profileId),
                ScheduleTransfer(
                    id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, label: "Homework hour",
                    days: [.monday, .tuesday, .wednesday, .thursday, .friday],
                    offHour: 16, offMinute: 0, onHour: 17, onMinute: 0,
                    gracePeriodMinutes: 0, isActive: false, profileId: nil),
            ],
            restrictions: [
                AppRestrictionTransfer(
                    id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
                    bundleIdentifier: "com.valvesoftware.steam", appName: "Steam",
                    restrictionType: .blocked, allowedScheduleId: nil, profileId: profileId),
                AppRestrictionTransfer(
                    id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
                    bundleIdentifier: "com.google.Chrome", appName: "Google Chrome",
                    restrictionType: .scheduledOnly, allowedScheduleId: schoolNightsId, profileId: nil),
            ])
    }

    func testFixtureDecodesIntoPolicyTransfer() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        XCTAssertEqual(try CloudCodec.decode(PolicyTransfer.self, from: data), expected)
        // The daemon's own XPC path uses the default decoder; it must agree.
        XCTAssertEqual(try JSONDecoder().decode(PolicyTransfer.self, from: data), expected)
    }

    func testEnvelopeAroundFixtureDecodes() throws {
        let policy = try String(contentsOf: Self.fixtureURL, encoding: .utf8)
        let json = """
        {"version":7,"activeProfileId":"6f1c2a8e-5b7d-4c3e-9a10-2b3c4d5e6f70",
         "manualOverride":{"enabled":false,"until":"2026-10-16T19:00:00Z"},"policy":\(policy)}
        """
        let envelope = try CloudCodec.decode(CloudPolicyEnvelope.self, from: Data(json.utf8))

        XCTAssertEqual(envelope.version, 7)
        XCTAssertEqual(envelope.activeProfileId, profileId)
        XCTAssertEqual(envelope.manualOverride, ManualInternetOverride(enabled: false, until: Self.date("2026-10-16T19:00:00Z")))
        XCTAssertEqual(envelope.policy, expected)
    }

    func testFollowsScheduleRuleResolvesAgainstFixtureSchedule() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        var daemonPolicy = DaemonPolicy.empty
        daemonPolicy.apply(try CloudCodec.decode(PolicyTransfer.self, from: data))
        daemonPolicy.activeProfileId = profileId

        // Thursday 2026-10-15 22:00 local is inside "School nights" (21:00 → 07:00).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let thursdayNight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 22))!
        XCTAssertFalse(daemonPolicy.isScheduledAppAllowed(scheduleId: schoolNightsId, at: thursdayNight))
        XCTAssertEqual(daemonPolicy.restrictedBundleIDs, ["com.valvesoftware.steam", "com.google.Chrome"])
    }

    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }
}
