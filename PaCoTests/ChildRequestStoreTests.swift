import XCTest
@testable import PaCoShared

final class ChildRequestStoreTests: XCTestCase {

    func testRecordedRequestIsPending() {
        var store = ChildRequestStore()
        let id = UUID()
        store.record(id: id, requestedMinutes: 30, reason: "homework")
        XCTAssertEqual(store.pending?.id, id)
        XCTAssertEqual(store.pending?.state, .sent)
        XCTAssertEqual(store.latest?.requestedMinutes, 30)
    }

    func testResolveApprovedConsumesRequest() {
        var store = ChildRequestStore()
        let id = UUID()
        let until = Date().addingTimeInterval(1800)
        store.record(id: id, requestedMinutes: 30, reason: "")
        XCTAssertTrue(store.resolve(id: id, approved: true, grantedUntil: until))
        XCTAssertNil(store.pending)
        XCTAssertEqual(store.latest?.state, .approved)
        XCTAssertEqual(store.latest?.grantedUntil, until)
        // A second reply for the same id is a replay and must be rejected.
        XCTAssertFalse(store.resolve(id: id, approved: true, grantedUntil: until))
    }

    func testResolveDeniedClearsGrant() {
        var store = ChildRequestStore()
        let id = UUID()
        store.record(id: id, requestedMinutes: 15, reason: "")
        XCTAssertTrue(store.resolve(id: id, approved: false))
        XCTAssertEqual(store.latest?.state, .denied)
        XCTAssertNil(store.latest?.grantedUntil)
    }

    func testUnknownIdIsRejected() {
        var store = ChildRequestStore()
        XCTAssertFalse(store.resolve(id: UUID(), approved: true))
    }

    func testRoundTripThroughFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paco-tests-\(UUID().uuidString)")
            .appendingPathComponent("child-requests.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var store = ChildRequestStore()
        let id = UUID()
        store.record(id: id, requestedMinutes: 45, reason: "game")
        try store.save(to: url)

        // Simulates an app relaunch: the pending request survives and can still be approved.
        var reloaded = ChildRequestStore.load(from: url)
        XCTAssertEqual(reloaded, store)
        XCTAssertTrue(reloaded.resolve(id: id, approved: true, grantedUntil: Date()))
    }

    func testMissingFileLoadsEmptyStore() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID()).json")
        XCTAssertTrue(ChildRequestStore.load(from: url).records.isEmpty)
    }

    func testPruneKeepsMostRecent() {
        var store = ChildRequestStore()
        for i in 0..<(ChildRequestStore.defaultKeepCount + 5) {
            store.record(id: UUID(), requestedMinutes: i, reason: "")
        }
        XCTAssertEqual(store.records.count, ChildRequestStore.defaultKeepCount)
        XCTAssertEqual(store.latest?.requestedMinutes, ChildRequestStore.defaultKeepCount + 4)
    }

    func testWithdrawPendingRejectsLateReply() {
        var store = ChildRequestStore()
        let id = UUID()
        store.record(id: id, requestedMinutes: 30, reason: "")
        store.withdrawPending()
        XCTAssertNil(store.pending)
        XCTAssertFalse(store.resolve(id: id, approved: true, grantedUntil: Date()))
    }

    func testExpirePendingDropsOnlyStaleUnanswered() {
        var store = ChildRequestStore()
        let old = UUID(), fresh = UUID(), oldAnswered = UUID()
        let now = Date()
        store.record(id: old, requestedMinutes: 30, reason: "", at: now.addingTimeInterval(-7200))
        store.record(id: oldAnswered, requestedMinutes: 30, reason: "", at: now.addingTimeInterval(-7200))
        store.record(id: fresh, requestedMinutes: 30, reason: "", at: now.addingTimeInterval(-60))
        store.resolve(id: oldAnswered, approved: false, at: now)
        store.expirePending(olderThan: 3600, now: now)
        XCTAssertEqual(Set(store.records.map(\.id)), [oldAnswered, fresh])
    }
}
