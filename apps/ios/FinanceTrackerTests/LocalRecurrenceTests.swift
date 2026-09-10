import XCTest
@testable import FinanceTracker

@MainActor
final class LocalRecurrenceTests: XCTestCase {
    private struct SharedFixtures: Decodable {
        struct Occurrence: Decodable { let scheduleId: UUID; let scheduledFor: Date; let id: UUID }
        struct Schedule: Decodable { let frequency: RecurrenceFrequency; let dates: [Date] }
        struct Deletion: Decodable { let action: RecurringDeletionAction; let remainingTransactions: Int; let remainingSchedules: Int }
        let occurrence: Occurrence; let schedules: [Schedule]; let deletions: [Deletion]
    }
    private func fixtures() throws -> SharedFixtures {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "local-first-recurrence", withExtension: "json"))
        return try LocalJSON.decoder.decode(SharedFixtures.self, from: Data(contentsOf: url))
    }
    func testSharedOccurrenceIdentityAndCalendarFixtures() throws {
        let fixture = try fixtures()
        XCTAssertEqual(occurrenceID(scheduleID: fixture.occurrence.scheduleId, scheduledFor: fixture.occurrence.scheduledFor), fixture.occurrence.id)
        for schedule in fixture.schedules {
            let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
            let start = schedule.dates.first!; let end = schedule.dates.last!
            _ = try repository.edit(now: start) { try $0.saveTransaction(request: LocalTestData.transaction(account.id, occurredAt: start, recurrence: RecurrenceRequest(frequency: schedule.frequency, endAt: end))) }
            try repository.edit(now: end) { try $0.materialize() }
            XCTAssertEqual(repository.snapshot.transactions.values.map(\.occurredAt).sorted(), schedule.dates)
        }
        for deletion in fixture.deletions {
            let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
            let start = LocalTestData.date("2100-01-31T12:00:00Z"); let now = start.addingTimeInterval(86400)
            _ = try repository.edit(now: now) { try $0.saveTransaction(request: LocalTestData.transaction(account.id, occurredAt: start, recurrence: RecurrenceRequest(frequency: .monthly, endAt: nil))) }
            let next = repository.snapshot.upcoming(now: now)[0]
            try repository.edit(now: now) { try $0.deleteOccurrence(scheduleID: next.id, date: next.occurredAt, action: deletion.action) }
            XCTAssertEqual(repository.snapshot.transactions.count, deletion.remainingTransactions)
            XCTAssertEqual(repository.snapshot.schedules.count, deletion.remainingSchedules)
        }
    }
    func testMonthEndLeapDayAndMissedOccurrencesSurviveReopening() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        let start = LocalTestData.date("2024-01-31T12:00:00Z")
        let end = LocalTestData.date("2024-04-30T12:00:00Z")
        _ = try repository.edit(now: start) { try $0.saveTransaction(request: LocalTestData.transaction(account.id, occurredAt: start, recurrence: RecurrenceRequest(frequency: .monthly, endAt: end))) }
        try repository.edit(now: end) { try $0.materialize() }
        let dates = repository.snapshot.transactions.values.map(\.occurredAt).sorted().map(LocalJSON.timestamp)
        XCTAssertEqual(dates, ["2024-01-31T12:00:00.000Z", "2024-02-29T12:00:00.000Z", "2024-03-31T12:00:00.000Z", "2024-04-30T12:00:00.000Z"])
        XCTAssertNil(repository.snapshot.schedules.values.first?.nextOccurrenceAt)
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        try reopened.edit(now: end.addingTimeInterval(86400 * 100)) { try $0.materialize() }
        XCTAssertEqual(reopened.snapshot.transactions.count, 4)
    }
    func testMoveRecordedDateKeepsImmutableOccurrenceIdentity() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        let start = LocalTestData.date("2100-01-31T12:00:00Z")
        let original = try repository.edit(now: start) { try $0.saveTransaction(request: LocalTestData.transaction(account.id, occurredAt: start, recurrence: RecurrenceRequest(frequency: .monthly, endAt: nil))) }
        let changedDate = start.addingTimeInterval(-86400)
        _ = try repository.edit(now: start) { try $0.saveTransaction(id: original.id, request: LocalTestData.transaction(account.id, occurredAt: changedDate, recurrence: RecurrenceRequest(frequency: .monthly, endAt: nil))) }
        XCTAssertEqual(repository.snapshot.transactions[original.id]?.scheduledFor, start)
        XCTAssertEqual(repository.snapshot.transactions[original.id]?.occurredAt, changedDate)
    }
    func testMovingProjectedDatePreservesIdentityWithoutAddingAnEarlyTransaction() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        let now = LocalTestData.date("2100-02-01T12:00:00Z")
        let start = LocalTestData.date("2100-01-31T12:00:00Z")
        _ = try repository.edit(now: now) { try $0.saveTransaction(request: LocalTestData.transaction(account.id, occurredAt: start, recurrence: RecurrenceRequest(frequency: .monthly, endAt: nil))) }
        let upcoming = try XCTUnwrap(repository.snapshot.upcoming(now: now).first)
        let originalSlot = upcoming.occurredAt; let replacement = LocalTestData.date("2100-03-03T12:00:00Z")
        try repository.edit(now: now) { try $0.updateUpcoming(upcoming, request: LocalTestData.transaction(account.id, occurredAt: replacement, recurrence: RecurrenceRequest(frequency: .monthly, endAt: nil))) }
        XCTAssertEqual(repository.snapshot.transactions.count, 1)
        try repository.edit(now: replacement) { try $0.materialize() }
        let generated = repository.snapshot.transactions[occurrenceID(scheduleID: upcoming.id, scheduledFor: originalSlot)]
        XCTAssertEqual(generated?.scheduledFor, originalSlot); XCTAssertEqual(generated?.occurredAt, replacement)
    }
    func testSkippedOccurrenceCannotReturnAfterCatchupOrRelaunch() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        let now = LocalTestData.date("2100-02-01T12:00:00Z")
        _ = try repository.edit(now: now) { try $0.saveTransaction(request: LocalTestData.transaction(account.id, occurredAt: LocalTestData.date("2100-01-31T12:00:00Z"), recurrence: RecurrenceRequest(frequency: .monthly, endAt: nil))) }
        let upcoming = try XCTUnwrap(repository.snapshot.upcoming(now: now).first)
        try repository.edit(now: now) { try $0.deleteOccurrence(scheduleID: upcoming.id, date: upcoming.occurredAt, action: .occurrence) }
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        try reopened.edit(now: LocalTestData.date("2100-03-31T12:00:00Z")) { try $0.materialize() }
        XCTAssertNil(reopened.snapshot.transactions[occurrenceID(scheduleID: upcoming.id, scheduledFor: upcoming.occurredAt)])
        XCTAssertEqual(reopened.snapshot.transactions.count, 2)
    }
    func testStopAndDeleteFutureKeepTheExistingHistoricalBehavior() throws {
        for action in [RecurringDeletionAction.stopRepeating, .occurrenceAndFuture] {
            let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
            let now = LocalTestData.date("2100-02-01T12:00:00Z")
            let historical = try repository.edit(now: now) { try $0.saveTransaction(request: LocalTestData.transaction(account.id, occurredAt: LocalTestData.date("2100-01-31T12:00:00Z"), recurrence: RecurrenceRequest(frequency: .monthly, endAt: nil))) }
            let upcoming = try XCTUnwrap(repository.snapshot.upcoming(now: now).first)
            try repository.edit(now: now) { try $0.deleteOccurrence(scheduleID: upcoming.id, date: upcoming.occurredAt, action: action) }
            XCTAssertTrue(repository.snapshot.schedules.isEmpty); XCTAssertNotNil(repository.snapshot.transactions[historical.id])
            XCTAssertEqual(repository.snapshot.transactions.count, action == .stopRepeating ? 2 : 1)
            XCTAssertTrue(repository.snapshot.transactions.values.allSatisfy { $0.recurringScheduleId == nil })
            XCTAssertEqual(repository.snapshot.pending.last?.mutation.authoredAt, now)
            XCTAssertEqual(repository.snapshot.pending.last?.mutation.recurrenceActions?.first?.targetScheduledFor, upcoming.occurredAt)
        }
    }
}
