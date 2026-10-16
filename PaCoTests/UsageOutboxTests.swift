import XCTest
@testable import PaCoShared

final class UsageOutboxTests: XCTestCase {
    private let day1 = ISO8601DateFormatter().date(from: "2026-10-15T22:00:00Z")!
    private var day2: Date { day1.addingTimeInterval(86_400) }
    private let t0 = ISO8601DateFormatter().date(from: "2026-10-16T12:00:00Z")!

    private func snapshot(_ day: Date, _ seconds: TimeInterval) -> UsageTransfer {
        UsageTransfer(date: day, profileId: nil, internetOnDuration: seconds, appUsage: [])
    }

    func testFirstSnapshotUploadsAtOnceThenAtMostEveryInterval() {
        var outbox = UsageOutbox()
        XCTAssertFalse(outbox.shouldUpload(now: t0))

        outbox.record(snapshot(day1, 10))
        XCTAssertTrue(outbox.shouldUpload(now: t0))
        outbox.markUploaded(outbox.pending, at: t0)
        XCTAssertTrue(outbox.pending.isEmpty)

        outbox.record(snapshot(day1, 40))
        XCTAssertFalse(outbox.shouldUpload(now: t0.addingTimeInterval(299)))
        XCTAssertTrue(outbox.shouldUpload(now: t0.addingTimeInterval(300)))
    }

    func testNewerSnapshotOfTheSameDayReplacesTheOlder() {
        var outbox = UsageOutbox()
        outbox.record(snapshot(day1, 10))
        outbox.record(snapshot(day1, 70))
        XCTAssertEqual(outbox.pending, [snapshot(day1, 70)])
    }

    func testDayRolloverUploadsImmediatelyWithYesterdaysFinalTotals() {
        var outbox = UsageOutbox()
        outbox.record(snapshot(day1, 10))
        outbox.markUploaded(outbox.pending, at: t0)
        outbox.record(snapshot(day1, 500))   // last snapshot of the day, not yet sent

        outbox.record(snapshot(day2, 5))     // midnight passed
        XCTAssertTrue(outbox.shouldUpload(now: t0.addingTimeInterval(1)))
        XCTAssertEqual(outbox.pending, [snapshot(day1, 500), snapshot(day2, 5)])
    }

    func testSnapshotThatChangedDuringUploadStaysPending() {
        var outbox = UsageOutbox()
        outbox.record(snapshot(day1, 10))
        let sent = outbox.pending
        outbox.record(snapshot(day1, 40))    // arrived while the request was in flight
        outbox.markUploaded(sent, at: t0)
        XCTAssertEqual(outbox.pending, [snapshot(day1, 40)])
    }

    func testFailureBacksOffUntilTheNextInterval() {
        var outbox = UsageOutbox()
        outbox.record(snapshot(day1, 10))
        outbox.markFailed(at: t0)
        XCTAssertFalse(outbox.shouldUpload(now: t0.addingTimeInterval(60)))
        XCTAssertTrue(outbox.shouldUpload(now: t0.addingTimeInterval(300)))
    }

    func testKeepsAtMostThreeDays() {
        var outbox = UsageOutbox()
        for i in 0..<5 { outbox.record(snapshot(day1.addingTimeInterval(Double(i) * 86_400), 1)) }
        XCTAssertEqual(outbox.pending.count, UsageOutbox.maxDays)
        XCTAssertEqual(outbox.pending.first?.date, day1.addingTimeInterval(2 * 86_400))
    }
}
