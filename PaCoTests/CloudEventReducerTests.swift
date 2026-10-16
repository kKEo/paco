import XCTest
@testable import PaCoShared

final class CloudEventReducerTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-16T18:00:00Z")!
    private let requestId = UUID()

    private func event(_ id: Int, _ kind: CloudEvent.Kind) -> CloudEvent { CloudEvent(id: id, kind: kind) }

    func testNewerPolicyVersionFetchesOnceAtTheEnd() {
        var state = CloudSyncState(eventCursor: 0, policyVersion: 2)
        let actions = CloudEventReducer.reduce([
            event(1, .policyChanged(version: 3)),
            event(2, .clearManualInternet),
            event(3, .policyChanged(version: 4)),
        ], state: &state, now: now)

        XCTAssertEqual(actions, [.clearManual, .fetchPolicy])
        XCTAssertEqual(state.eventCursor, 3)
        XCTAssertEqual(state.policyVersion, 2, "set only once the envelope was applied")
    }

    func testPolicyVersionAlreadyHeldIsSkipped() {
        var state = CloudSyncState(eventCursor: 0, policyVersion: 5)
        XCTAssertEqual(CloudEventReducer.reduce([event(1, .policyChanged(version: 5))], state: &state, now: now), [])
        XCTAssertEqual(state.eventCursor, 1)
    }

    func testReplayedEventsAtOrBelowTheCursorAreSkipped() {
        var state = CloudSyncState(eventCursor: 10, policyVersion: 1)
        let actions = CloudEventReducer.reduce([
            event(9, .setManualInternet(enabled: false, minutes: 10, until: now.addingTimeInterval(600))),
            event(10, .clearManualInternet),
            event(11, .clearManualInternet),
        ], state: &state, now: now)

        XCTAssertEqual(actions, [.clearManual])
        XCTAssertEqual(state.eventCursor, 11)
    }

    func testEventsAreAppliedInIdOrder() {
        var state = CloudSyncState(eventCursor: 0, policyVersion: 1)
        let until = now.addingTimeInterval(600)
        let actions = CloudEventReducer.reduce([
            event(2, .clearManualInternet),
            event(1, .setManualInternet(enabled: true, minutes: 10, until: until)),
        ], state: &state, now: now)

        XCTAssertEqual(actions, [.setManual(enabled: true, until: until), .clearManual])
    }

    func testApprovalResolvesAndGrantsUntilTheAbsoluteEnd() {
        var state = CloudSyncState(eventCursor: 0, policyVersion: 1)
        let until = now.addingTimeInterval(45 * 60)
        let actions = CloudEventReducer.reduce([
            event(1, .approveExtension(requestId: requestId, grantedMinutes: 45, grantedUntil: until)),
        ], state: &state, now: now)

        XCTAssertEqual(actions, [
            .resolveRequest(requestId: requestId, approved: true, grantedUntil: until),
            .grantOverride(requestId: requestId, until: until),
        ])
    }

    func testLateApprovalResolvesButGrantsNothing() {
        var state = CloudSyncState(eventCursor: 0, policyVersion: 1)
        let until = now.addingTimeInterval(-60)
        let actions = CloudEventReducer.reduce([
            event(1, .approveExtension(requestId: requestId, grantedMinutes: 30, grantedUntil: until)),
        ], state: &state, now: now)

        XCTAssertEqual(actions, [.resolveRequest(requestId: requestId, approved: true, grantedUntil: until)])
    }

    func testExpiredManualToggleIsNotApplied() {
        var state = CloudSyncState(eventCursor: 0, policyVersion: 1)
        let actions = CloudEventReducer.reduce([
            event(1, .setManualInternet(enabled: false, minutes: 10, until: now.addingTimeInterval(-1))),
        ], state: &state, now: now)
        XCTAssertEqual(actions, [])
    }

    func testDenyResolvesTheRequest() {
        var state = CloudSyncState(eventCursor: 0, policyVersion: 1)
        XCTAssertEqual(
            CloudEventReducer.reduce([event(1, .denyExtension(requestId: requestId))], state: &state, now: now),
            [.resolveRequest(requestId: requestId, approved: false, grantedUntil: nil)])
    }

    func testProfileChangeSetsProfileAndRefetches() {
        var state = CloudSyncState(eventCursor: 0, policyVersion: 1)
        let profile = UUID()
        XCTAssertEqual(
            CloudEventReducer.reduce([event(1, .activeProfileChanged(profileId: profile))], state: &state, now: now),
            [.setActiveProfile(profile), .fetchPolicy])
    }

    func testUnknownTypesAreSkippedButAcknowledged() {
        var state = CloudSyncState(eventCursor: 0, policyVersion: 1)
        XCTAssertEqual(CloudEventReducer.reduce([event(1, .unknown(type: "future"))], state: &state, now: now), [])
        XCTAssertEqual(state.eventCursor, 1)
    }

    func testUnenrolledStopsTheBatchEvenAtTheCursor() {
        // The server's synthetic `unenrolled` carries id == cursor.
        var state = CloudSyncState(eventCursor: 7, policyVersion: 1)
        let actions = CloudEventReducer.reduce([
            event(7, .unenrolled),
            event(8, .clearManualInternet),
        ], state: &state, now: now)
        XCTAssertEqual(actions, [.unenroll])
    }
}
