import XCTest
@testable import PaCoShared

final class UsageLedgerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testOpenAppAccruesForegroundTime() {
        var ledger = UsageLedger()
        ledger.activate(bundleId: "com.a", appName: "A", at: at(0))
        let snap = ledger.snapshot(at: at(90))
        XCTAssertEqual(snap.first?.bundleIdentifier, "com.a")
        XCTAssertEqual(snap.first?.duration ?? 0, 90, accuracy: 0.001, "time shows while the app is still open")
    }

    func testOnlyFrontmostAppAccrues() {
        var ledger = UsageLedger()
        ledger.launch(bundleId: "com.a", appName: "A")
        ledger.launch(bundleId: "com.b", appName: "B")
        ledger.activate(bundleId: "com.a", appName: "A", at: at(0))
        ledger.activate(bundleId: "com.b", appName: "B", at: at(60))
        ledger.activate(bundleId: "com.a", appName: "A", at: at(100))
        let snap = Dictionary(uniqueKeysWithValues: ledger.snapshot(at: at(130)).map { ($0.bundleIdentifier, $0) })
        XCTAssertEqual(snap["com.a"]?.duration ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(snap["com.b"]?.duration ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(snap["com.a"]?.launchCount, 1)
    }

    func testTerminateStopsAccrual() {
        var ledger = UsageLedger()
        ledger.activate(bundleId: "com.a", appName: "A", at: at(0))
        ledger.terminate(bundleId: "com.a", at: at(30))
        XCTAssertNil(ledger.currentForegroundBundleId)
        XCTAssertEqual(ledger.snapshot(at: at(500)).first?.duration ?? 0, 30, accuracy: 0.001)
    }

    func testTerminatingBackgroundAppDoesNotAffectForeground() {
        var ledger = UsageLedger()
        ledger.activate(bundleId: "com.a", appName: "A", at: at(0))
        ledger.terminate(bundleId: "com.b", at: at(10))
        XCTAssertEqual(ledger.currentForegroundBundleId, "com.a")
    }

    func testAlreadyRunningAppCountsFromActivation() {
        // Agent starts while A is frontmost: activation at start, no launch event.
        var ledger = UsageLedger()
        ledger.activate(bundleId: "com.a", appName: "A", at: at(0))
        let entry = ledger.snapshot(at: at(45)).first
        XCTAssertEqual(entry?.duration ?? 0, 45, accuracy: 0.001)
        XCTAssertEqual(entry?.launchCount, 0)
    }

    func testSeedFromSnapshotContinuesTotals() {
        var ledger = UsageLedger(entries: [AppUsageEntry(bundleIdentifier: "com.a", appName: "A", duration: 100, launchCount: 2)])
        ledger.activate(bundleId: "com.a", appName: "A", at: at(0))
        let entry = ledger.snapshot(at: at(20)).first
        XCTAssertEqual(entry?.duration ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(entry?.launchCount, 2)
    }

    func testResetKeepsForegroundAppAccruingFromResetTime() {
        var ledger = UsageLedger()
        ledger.activate(bundleId: "com.a", appName: "A", at: at(0))
        ledger.reset(at: at(100))
        XCTAssertEqual(ledger.snapshot(at: at(130)).first?.duration ?? 0, 30, accuracy: 0.001)
    }

    func testNilActivationPausesAccrual() {
        var ledger = UsageLedger()
        ledger.activate(bundleId: "com.a", appName: "A", at: at(0))
        ledger.activate(bundleId: nil, at: at(10))
        XCTAssertEqual(ledger.snapshot(at: at(100)).first?.duration ?? 0, 10, accuracy: 0.001)
    }
}
