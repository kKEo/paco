import XCTest
@testable import PaCoShared

final class CloudCodecTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testDatesAreISO8601WithoutFractionalSeconds() throws {
        let body = CloudUsageUpload(timeZone: "Europe/Warsaw", days: [
            UsageTransfer(date: date("2026-10-15T22:00:00Z"), profileId: nil, internetOnDuration: 60.5, appUsage: []),
        ])
        let json = String(decoding: try CloudCodec.encode(body), as: UTF8.self)
        XCTAssertTrue(json.contains(#""date":"2026-10-15T22:00:00Z""#), json)
    }

    func testDecodesServerEventsResponse() throws {
        let json = """
        {"events":[
          {"id":4,"type":"policyChanged","payload":{"version":3},"createdAt":"2026-10-16T18:00:00Z"},
          {"id":5,"type":"activeProfileChanged","payload":{"profileId":null},"createdAt":"2026-10-16T18:00:00Z"},
          {"id":6,"type":"approveExtension","payload":{"requestId":"9a7d0e2c-5b7d-4c3e-9a10-2b3c4d5e6f70","grantedMinutes":45,"grantedUntil":"2026-10-16T18:45:00Z"},"createdAt":"2026-10-16T18:00:00Z"},
          {"id":7,"type":"denyExtension","payload":{"requestId":"9a7d0e2c-5b7d-4c3e-9a10-2b3c4d5e6f70"},"createdAt":"2026-10-16T18:00:00Z"},
          {"id":8,"type":"setManualInternet","payload":{"enabled":false,"minutes":10,"until":"2026-10-16T18:10:00Z"},"createdAt":"2026-10-16T18:00:00Z"},
          {"id":9,"type":"clearManualInternet","payload":{},"createdAt":"2026-10-16T18:00:00Z"},
          {"id":10,"type":"somethingNew","payload":{"x":1},"createdAt":"2026-10-16T18:00:00Z"},
          {"id":10,"type":"unenrolled","payload":{},"createdAt":"2026-10-16T18:00:00Z"}
        ],"nextCursor":10,"serverTime":"2026-10-16T18:00:01Z"}
        """
        let response = try CloudCodec.decode(CloudEventsResponse.self, from: Data(json.utf8))
        let requestId = UUID(uuidString: "9A7D0E2C-5B7D-4C3E-9A10-2B3C4D5E6F70")!

        XCTAssertEqual(response.nextCursor, 10)
        XCTAssertNil(response.retryAfter)
        XCTAssertEqual(response.events.map(\.kind), [
            .policyChanged(version: 3),
            .activeProfileChanged(profileId: nil),
            .approveExtension(requestId: requestId, grantedMinutes: 45, grantedUntil: date("2026-10-16T18:45:00Z")),
            .denyExtension(requestId: requestId),
            .setManualInternet(enabled: false, minutes: 10, until: date("2026-10-16T18:10:00Z")),
            .clearManualInternet,
            .unknown(type: "somethingNew"),
            .unenrolled,
        ])
    }

    func testDecodesBusyServerRetryAfter() throws {
        let json = #"{"events":[],"nextCursor":3,"serverTime":"2026-10-16T18:00:00Z","retryAfter":5}"#
        XCTAssertEqual(try CloudCodec.decode(CloudEventsResponse.self, from: Data(json.utf8)).retryAfter, 5)
    }

    func testDecodesEnrollAndHeartbeatResponses() throws {
        let enroll = try CloudCodec.decode(CloudEnrollResponse.self, from: Data("""
        {"deviceId":"01a1444e-ff94-70fd-82bd-5a8ff2932945","deviceName":"Test Mac",
         "deviceToken":"pcd_01a1444e-ff94-70fd-82bd-5a8ff2932945.secret","policyVersion":1,
         "eventCursor":0,"serverTime":"2026-10-16T10:43:10Z"}
        """.utf8))
        XCTAssertEqual(enroll.deviceId, UUID(uuidString: "01A1444E-FF94-70FD-82BD-5A8FF2932945"))
        XCTAssertEqual(enroll.policyVersion, 1)

        let heartbeat = try CloudCodec.decode(CloudHeartbeatResponse.self, from: Data("""
        {"serverTime":"2026-10-16T10:43:10Z","policyVersion":4,"policyStale":true,"pendingEvents":2}
        """.utf8))
        XCTAssertTrue(heartbeat.policyStale)
    }

    func testDecodesPINVerifyResultFromServer() throws {
        let result = try CloudCodec.decode(PINVerifyResult.self, from: Data("""
        {"nonce":"c0ffee00-5b7d-4c3e-9a10-2b3c4d5e6f70","outcome":"lockedOut","lockedOutUntil":"2026-10-16T18:05:00Z"}
        """.utf8))
        XCTAssertEqual(result.outcome, .lockedOut)
        XCTAssertEqual(result.lockedOutUntil, date("2026-10-16T18:05:00Z"))

        let ok = try CloudCodec.decode(PINVerifyResult.self, from: Data("""
        {"nonce":"c0ffee00-5b7d-4c3e-9a10-2b3c4d5e6f70","outcome":"success","lockedOutUntil":null}
        """.utf8))
        XCTAssertNil(ok.lockedOutUntil)
    }

    func testDeviceStatusReflectsPolicyAndOverrides() {
        let now = date("2026-10-16T18:00:00Z")
        let requestId = UUID()
        var policy = DaemonPolicy.empty
        policy.manualOverride = ManualInternetOverride(enabled: false, until: now.addingTimeInterval(600))
        policy.override = InternetOverride(requestId: requestId, grantedUntil: now.addingTimeInterval(-1))

        let status = CloudDeviceStatus(policy: policy, internetEnabled: false, at: now)

        XCTAssertEqual(status.action, "blocked")
        XCTAssertEqual(status.manualOverride?.enabled, false)
        XCTAssertNil(status.override, "an expired grant is not reported")
        XCTAssertNil(status.graceRemainingSeconds)
    }

    func testXPCEnvelopeRoundTrips() throws {
        let requests: [CloudXPCRequest] = [
            .enroll(serverURL: "https://paco.example.com", code: "ABCD-1234", deviceName: "Mac"),
            .unenroll, .status,
            .submitExtensionRequest(requestId: UUID(), requestedMinutes: 30, reason: "essay"),
            .withdrawRequest(requestId: UUID()),
            .verifyPIN(nonce: UUID(), pin: "123456"),
        ]
        for request in requests {
            XCTAssertEqual(try CloudCodec.decode(CloudXPCRequest.self, from: CloudCodec.encode(request)), request)
        }
        let response = CloudXPCResponse(ok: true, status: .notEnrolled,
                                        pinResult: PINVerifyResult(nonce: UUID(), outcome: .success))
        XCTAssertEqual(try CloudCodec.decode(CloudXPCResponse.self, from: CloudCodec.encode(response)), response)
    }
}
