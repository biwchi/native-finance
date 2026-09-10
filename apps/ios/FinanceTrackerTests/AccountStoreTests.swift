import XCTest
@testable import FinanceTracker

@MainActor
final class AccountStoreTests: XCTestCase {
    func testOrderPersistsLocallyWithAnAtomicMutation() async throws {
        let repository = try LocalTestData.repository()
        let first = try LocalTestData.account(repository, name: "First")
        let second = try LocalTestData.account(repository, name: "Second")
        let store = AccountStore(repository: repository)
        try await store.reorderAccounts([second, first])
        XCTAssertEqual(store.accounts.map(\.id), [second.id, first.id])
        XCTAssertEqual(repository.snapshot.pending.last?.mutation.changes.count, 2)
        XCTAssertEqual(try LocalFinanceRepository(path: repository.requireDatabase().pool.path).snapshot.sortedAccounts.map(\.id), [second.id, first.id])
    }
    func testInvalidOrderLeavesPreviousOrderUnchanged() async throws {
        let repository = try LocalTestData.repository(); let first = try LocalTestData.account(repository)
        _ = try LocalTestData.account(repository, name: "Second")
        let store = AccountStore(repository: repository); let before = store.accounts
        do { try await store.reorderAccounts([first]); XCTFail("An incomplete order must fail") } catch {}
        XCTAssertEqual(store.accounts, before)
    }
    func testDeleteClearsSelectionAndCascadesImmediatelyOffline() async throws {
        let repository = try LocalTestData.repository(); let first = try LocalTestData.account(repository)
        let store = AccountStore(repository: repository); store.selectedAccountID = first.id
        _ = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(first.id)) }
        try await store.deleteAccount(first)
        XCTAssertNil(store.selectedAccountID); XCTAssertTrue(store.accounts.isEmpty); XCTAssertTrue(repository.snapshot.transactions.isEmpty)
        XCTAssertTrue(repository.snapshot.pending.last!.mutation.changes.allSatisfy { $0.data == nil })
    }
}
