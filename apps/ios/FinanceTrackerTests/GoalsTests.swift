import XCTest
@testable import FinanceTracker

@MainActor
final class GoalsTests: XCTestCase {
    func testSaveReopenAndClearDeadlineWithAccountDependency() throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let accountMutation = try XCTUnwrap(repository.snapshot.pending.last)
        let store = GoalStore(repository: repository)
        let goal = try store.save(name: " Dream car ", accountID: account.id, targetAmount: "25000.1234",
                                  icon: "car", color: .blue, deadline: "2028-02-29")
        XCTAssertEqual(goal.name, "Dream car")
        XCTAssertEqual(repository.snapshot.pending.last?.dependencies, [accountMutation.id])
        XCTAssertEqual(repository.snapshot.pending.last?.mutation.changes.first?.data?["targetAmount"]?.string, "25000.1234")
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        let persisted = try XCTUnwrap(store.goals.first)
        XCTAssertEqual(reopened.snapshot.goals[goal.id], persisted)
        let updated = try store.save(id: goal.id, name: "Car", accountID: account.id, targetAmount: "30000",
                                     icon: "car", color: .purple, deadline: nil)
        XCTAssertEqual(updated.createdAt, persisted.createdAt)
        XCTAssertNil(updated.deadline)
        XCTAssertEqual(store.goals.first?.color, .purple)
        XCTAssertTrue(repository.snapshot.transactions.isEmpty)
    }

    func testInvalidGoalsDoNotLeavePartialRecordsOrOutboxOperations() throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = GoalStore(repository: repository)
        let pending = repository.snapshot.pending.count
        for amount in ["0", "-5", "1.12345", "1000000000000000", "NaN", ""] {
            XCTAssertThrowsError(try store.save(name: "Goal", accountID: account.id, targetAmount: amount,
                                                icon: "car", color: .blue, deadline: nil))
        }
        XCTAssertThrowsError(try store.save(name: " ", accountID: account.id, targetAmount: "1", icon: "car", color: .blue, deadline: nil))
        XCTAssertThrowsError(try store.save(name: "Goal", accountID: UUID(), targetAmount: "1", icon: "car", color: .blue, deadline: nil))
        XCTAssertThrowsError(try store.save(name: "Goal", accountID: account.id, targetAmount: "1", icon: "car", color: .blue, deadline: "2026-02-29"))
        XCTAssertThrowsError(try store.save(id: UUID(), name: "Missing", accountID: account.id, targetAmount: "1", icon: "car", color: .blue, deadline: nil))
        XCTAssertTrue(store.goals.isEmpty)
        XCTAssertEqual(repository.snapshot.pending.count, pending)
    }

    func testOrderPersistsWithoutReplacingNewerGoalDetails() throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = GoalStore(repository: repository)
        let first = try store.save(name: "First", accountID: account.id, targetAmount: "100", icon: "car", color: .blue, deadline: nil)
        let second = try store.save(name: "Second", accountID: account.id, targetAmount: "200", icon: "home", color: .green, deadline: nil)
        _ = try store.save(id: first.id, name: "Updated", accountID: account.id, targetAmount: "300", icon: "car", color: .teal, deadline: nil)
        try store.reorder([second.id, first.id])
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        XCTAssertEqual(reopened.snapshot.sortedGoals.map(\.id), [second.id, first.id])
        XCTAssertEqual(reopened.snapshot.goals[first.id]?.name, "Updated")
        XCTAssertEqual(reopened.snapshot.goals[first.id]?.targetAmount, "300")
        XCTAssertThrowsError(try store.reorder([first.id, first.id]))
        XCTAssertThrowsError(try store.reorder([first.id]))
    }

    func testGoalDeletionKeepsMoneyAndAccountDeletionRemovesItsGoals() throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let other = try LocalTestData.account(repository, name: "Other")
        let income = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id, amount: "14000", kind: .income)) }
        let store = GoalStore(repository: repository)
        let goal = try store.save(name: "Car", accountID: account.id, targetAmount: "25000", icon: "car", color: .blue, deadline: nil)
        try store.delete(goal)
        XCTAssertNotNil(repository.snapshot.accounts[account.id])
        XCTAssertNotNil(repository.snapshot.transactions[income.id])
        XCTAssertEqual(repository.snapshot.pending.last?.mutation.changes.map(\.entity), ["goal"])
        let dependent = try store.save(name: "Car", accountID: account.id, targetAmount: "25000", icon: "car", color: .blue, deadline: nil)
        let independent = try store.save(name: "Home", accountID: other.id, targetAmount: "50000", icon: "home", color: .green, deadline: nil)
        try repository.edit { $0.deleteAccount(account.id) }
        XCTAssertNil(repository.snapshot.goals[dependent.id])
        XCTAssertNotNil(repository.snapshot.goals[independent.id])
        XCTAssertTrue(repository.snapshot.pending.last!.mutation.changes.contains { $0.entity == "goal" && $0.data == nil })
        try repository.deleteAllData()
        XCTAssertTrue(store.goals.isEmpty)
    }

    func testProgressTracksTopUpsSpendingAndTransfersWithoutMovingGoals() throws {
        let repository = try LocalTestData.repository()
        let source = try repository.edit { try $0.saveAccount(name: "Main", currency: "USD", icon: "wallet", color: .blue, initialBalance: "100") }
        let destination = try LocalTestData.account(repository, name: "Car")
        let store = GoalStore(repository: repository)
        let goal = try store.save(name: "Car", accountID: destination.id, targetAmount: "50", icon: "car", color: .blue, deadline: nil)
        let transactions = TransactionStore(repository: repository)
        _ = try repository.edit { try $0.transfer(TransferRequest(fromAccountId: source.id, toAccountId: destination.id, amount: "60", note: nil, occurredAt: LocalTestData.now)) }
        let balance = try XCTUnwrap(transactions.balance(accountID: destination.id, currency: "USD", rates: nil))
        XCTAssertEqual(balance, 60)
        XCTAssertEqual(GoalProgress(balance: balance, target: goal.target).remaining, 0)
        XCTAssertTrue(GoalProgress(balance: balance, target: goal.target).isComplete)
        XCTAssertEqual(GoalProgress(balance: balance, target: goal.target).fraction, 1)
        _ = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(destination.id, amount: "20")) }
        let afterSpending = try XCTUnwrap(transactions.balance(accountID: destination.id, currency: "USD", rates: nil))
        XCTAssertEqual(GoalProgress(balance: afterSpending, target: goal.target).remaining, 10)
        XCTAssertFalse(GoalProgress(balance: afterSpending, target: goal.target).isComplete)
        XCTAssertEqual(store.goals.map(\.id), [goal.id])
        XCTAssertEqual(GoalProgress(balance: -10, target: 50).remaining, 60)
        XCTAssertEqual(GoalProgress(balance: -10, target: 50).fraction, 0)
        _ = try repository.edit { try $0.saveTransaction(request: TransactionRequest(accountId: destination.id, kind: .income, amount: "1", categoryId: nil, note: nil, occurredAt: LocalTestData.now, currency: "EUR")) }
        XCTAssertNil(transactions.balance(accountID: destination.id, currency: "USD", rates: nil))
    }

    func testRemoteGoalsAndTombstonesUseTheSameLocalSnapshot() throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let pending = try XCTUnwrap(repository.snapshot.pending.first)
        try repository.acknowledge(LocalTestData.ack(pending), for: pending)
        let workspace = try XCTUnwrap(repository.value(UUID.self, key: "workspaceID"))
        let remote = SavingsGoal(id: UUID(), name: "Remote", accountId: account.id, targetAmount: "500.0000",
                                 icon: "target", color: .blue, deadline: "2026-12-31", sortOrder: 0,
                                 createdAt: LocalTestData.now, updatedAt: LocalTestData.now)
        let record = SyncRecord(entity: "goal", key: remote.id.uuidString.lowercased(), version: "2", data: try LocalJSON.object(remote))
        try repository.receive(SyncSnapshot(workspaceId: workspace, generation: 1, cursor: "2", records: [record]))
        XCTAssertEqual(repository.snapshot.goals[remote.id], remote)
        try repository.receive(SyncSnapshot(workspaceId: workspace, generation: 1, cursor: "3", records: [SyncRecord(entity: "goal", key: record.key, version: "3", data: nil)]))
        XCTAssertNil(repository.snapshot.goals[remote.id])
    }

    func testDeadlineKeepsTheSelectedDayAcrossTimeZones() throws {
        for offset in [-12, 0, 6, 14] {
            let zone = try XCTUnwrap(TimeZone(secondsFromGMT: offset * 3600))
            let date = try XCTUnwrap(GoalDeadline.date(from: "2028-02-29", timeZone: zone))
            XCTAssertEqual(GoalDeadline.string(from: date, timeZone: zone), "2028-02-29")
        }
        for invalid in ["2026-02-29", "2026-04-31", "2026-13-01", "2026-1-1", "2026-01-01T00:00:00Z"] {
            XCTAssertNil(GoalDeadline.date(from: invalid))
        }
    }
}
