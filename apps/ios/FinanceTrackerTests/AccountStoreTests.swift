import XCTest
@testable import FinanceTracker

@MainActor
final class AccountStoreTests: XCTestCase {
    func testInitialBalancePersistsAndSyncsWithoutCreatingIncome() async throws {
        let repository = try LocalTestData.repository()
        let store = AccountStore(repository: repository)
        let account = try await store.createAccount(name: "Everyday", currency: "USD", icon: "wallet", iconColor: .blue, initialBalance: "1 234,5678")
        let transactions = TransactionStore(repository: repository)
        XCTAssertEqual(account.initialBalance, "1234.5678")
        XCTAssertEqual(transactions.balance(accountID: account.id, currency: "USD", rates: nil), Decimal(string: "1234.5678"))
        XCTAssertTrue(transactions.allTransactions.isEmpty)
        let pending = try XCTUnwrap(repository.snapshot.pending.last)
        XCTAssertEqual(pending.mutation.changes.map(\.entity), ["account"])
        XCTAssertNil(pending.mutation.changes.first?.data?["type"])
        XCTAssertEqual(pending.mutation.changes.first?.data?["initialBalance"]?.string, "1234.5678")
        try repository.acknowledge(LocalTestData.ack(pending), for: pending)
        try repository.acknowledge(LocalTestData.ack(pending), for: pending)
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        XCTAssertEqual(reopened.snapshot.accounts[account.id]?.initialBalance, "1234.5678")
        XCTAssertEqual(TransactionStore(repository: reopened).balance(accountID: nil, currency: "USD", rates: nil), Decimal(string: "1234.5678"))
        XCTAssertTrue(reopened.snapshot.transactions.isEmpty)
    }

    func testEditingAndReorderingPreserveOpeningBalanceAndRecordedActivity() async throws {
        let repository = try LocalTestData.repository()
        let store = AccountStore(repository: repository)
        let account = try await store.createAccount(name: "Everyday", currency: "USD", icon: "wallet", iconColor: .blue, initialBalance: "100")
        _ = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id, amount: "25")) }
        _ = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id, amount: "10", kind: .income)) }
        let transactions = TransactionStore(repository: repository)
        XCTAssertEqual(transactions.balance(accountID: account.id, currency: "USD", rates: nil), 85)
        let edited = try await store.updateAccount(id: account.id, name: "Renamed", currency: "USD", icon: "bank", iconColor: .red)
        XCTAssertEqual(edited.initialBalance, "100")
        try await store.reorderAccounts([edited])
        XCTAssertEqual(store.accounts.first?.initialBalance, "100")
        let recorded = repository.snapshot.transactions
        _ = try await store.updateAccount(id: account.id, name: "Renamed", currency: "USD", icon: "bank", iconColor: .red, initialBalance: "-50.25")
        XCTAssertEqual(transactions.balance(accountID: nil, currency: "USD", rates: nil), Decimal(string: "-65.25"))
        XCTAssertEqual(repository.snapshot.transactions, recorded)
        try await store.deleteAccount(store.accounts[0])
        XCTAssertEqual(transactions.balance(accountID: nil, currency: "USD", rates: nil), 0)
    }

    func testOpeningBalancesConvertWithoutReturningPartialTotals() async throws {
        let repository = try LocalTestData.repository()
        let store = AccountStore(repository: repository)
        let euros = try await store.createAccount(name: "Euro", currency: "EUR", icon: "bank", iconColor: .blue, initialBalance: "80")
        _ = try await store.createAccount(name: "Dollar", currency: "USD", icon: "bank", iconColor: .blue, initialBalance: "-25")
        _ = try await store.createAccount(name: "Empty", currency: "JPY", icon: "bank", iconColor: .blue)
        let transactions = TransactionStore(repository: repository)
        let rates = ExchangeRateSnapshot(baseCurrency: "USD", reportingCurrency: "USD",
            quotes: [ExchangeRateQuote(currency: "EUR", rate: "0.8", effectiveDate: "2026-09-12")], fetchedAt: .now, stale: false)
        XCTAssertEqual(transactions.balance(accountID: euros.id, currency: "EUR", rates: nil), 80)
        XCTAssertEqual(transactions.balance(accountID: nil, currency: "USD", rates: rates), 75)
        XCTAssertNil(transactions.balance(accountID: nil, currency: "USD", rates: nil))
    }

    func testInvalidInitialBalanceCannotCommitAnAccountOrOutboxEntry() async throws {
        let repository = try LocalTestData.repository()
        let store = AccountStore(repository: repository)
        for invalid in ["1.23456", "NaN", "1e3", "1000000000000000", "1/2", "--1"] {
            do {
                _ = try await store.createAccount(name: "Invalid", currency: "USD", icon: "bank", iconColor: .blue, initialBalance: invalid)
                XCTFail("Accepted invalid balance: \(invalid)")
            } catch {}
        }
        XCTAssertTrue(repository.snapshot.accounts.isEmpty)
        XCTAssertTrue(repository.snapshot.pending.isEmpty)
        XCTAssertEqual(try Account.initialBalanceValue(""), "0")
        XCTAssertEqual(try Account.initialBalanceValue("-0.0000"), "0")
        XCTAssertEqual(try Account.initialBalanceValue("-999999999999999.9999"), "-999999999999999.9999")
    }

    func testLegacyAccountsDecodeWithoutTypeOrInitialBalanceRequirements() throws {
        let repository = try LocalTestData.repository()
        let original = try LocalTestData.account(repository)
        var legacy = try LocalJSON.object(original)
        legacy.removeValue(forKey: "initialBalance")
        legacy["type"] = .string("checking")
        let decoded = try LocalJSON.decode(Account.self, legacy)
        XCTAssertEqual(decoded.initialBalance, "0")
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertNil(try LocalJSON.object(decoded)["type"])
    }

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
