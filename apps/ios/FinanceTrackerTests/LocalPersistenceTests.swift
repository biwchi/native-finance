import XCTest
import GRDB
@testable import FinanceTracker

@MainActor
enum LocalTestData {
    nonisolated static let now = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01 UTC
    static func repository(imported: Bool = true) throws -> LocalFinanceRepository {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("finance-test-\(UUID()).sqlite").path
        let repository = try LocalFinanceRepository(path: path)
        if imported { try repository.importSnapshot(SyncSnapshot(workspaceId: UUID(), generation: 1, cursor: "0", records: [])) }
        return repository
    }
    static func account(_ repository: LocalFinanceRepository, name: String = "Main", currency: String = "USD") throws -> Account {
        try repository.edit(now: now) { try $0.saveAccount(name: name, type: .checking, currency: currency, icon: "wallet", color: .blue) }
    }
    static func transaction(_ accountID: UUID, amount: String = "12.3456", kind: TransactionKind = .expense, categoryID: UUID? = nil, occurredAt: Date = now, recurrence: RecurrenceRequest? = nil) -> TransactionRequest {
        TransactionRequest(accountId: accountID, kind: kind, amount: amount, categoryId: categoryID, merchant: "Coffee", note: "Morning", occurredAt: occurredAt, recurrence: recurrence)
    }
    static func ack(_ pending: PendingMutation, version: String = "1") -> SyncResult {
        SyncResult(mutationId: pending.id, status: "accepted", generation: pending.mutation.generation, records: pending.mutation.changes.map { SyncRecord(entity: $0.entity, key: $0.key, version: version, data: $0.data) }, message: nil)
    }
    static func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
}

@MainActor
final class LocalPersistenceTests: XCTestCase {
    func testOfflineSavePublishesBeforeUploadAndSurvivesReopening() async throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        var signals = 0; repository.onMutation = { signals += 1 }
        let saved = try await store.createTransaction(LocalTestData.transaction(account.id))
        XCTAssertEqual(store.allTransactions.first?.id, saved.id); XCTAssertEqual(store.state, .loaded); XCTAssertEqual(signals, 1)
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        XCTAssertEqual(reopened.snapshot.transactions[saved.id]?.amount, "12.3456")
        XCTAssertEqual(reopened.snapshot.pending.count, 2)
        XCTAssertTrue(reopened.snapshot.imported)
    }
    func testDependentOfflineCreationAndTransferAreAtomic() async throws {
        let repository = try LocalTestData.repository(); let first = try LocalTestData.account(repository); let second = try LocalTestData.account(repository, name: "Cash")
        let store = TransactionStore(repository: repository)
        _ = try await store.createTransaction(LocalTestData.transaction(first.id, amount: "100", kind: .income))
        let transfer = try await store.createTransfer(TransferRequest(fromAccountId: first.id, toAccountId: second.id, amount: "30", merchant: nil, payee: nil, note: nil, occurredAt: LocalTestData.now))
        let pending = repository.snapshot.pending.last!
        XCTAssertEqual(pending.mutation.changes.count, 2); XCTAssertEqual(Set(pending.dependencies), Set(repository.snapshot.pending.prefix(2).map(\.id)))
        XCTAssertEqual(store.balance(accountID: first.id, currency: "USD", rates: nil), 70)
        XCTAssertEqual(store.balance(accountID: second.id, currency: "USD", rates: nil), 30)
        XCTAssertEqual(store.balance(accountID: nil, currency: "USD", rates: nil), 100)
        XCTAssertNotEqual(transfer.source.id, transfer.destination.id)
        XCTAssertEqual(store.transactions(for: second.id).map(\.id), [transfer.destination.id])
    }
    func testFailedLocalCommitPreservesDraftAndAllPreviousRows() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        try repository.saveValue("Coffee 12", key: "quickEntryText")
        let pendingCount = repository.snapshot.pending.count
        try repository.requireDatabase().write { db in try db.execute(sql: "CREATE TRIGGER fail_save BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT, 'disk full'); END") }
        XCTAssertThrowsError(try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id)) })
        XCTAssertTrue(repository.snapshot.transactions.isEmpty); XCTAssertEqual(repository.snapshot.pending.count, pendingCount)
        XCTAssertEqual(try repository.value(String.self, key: "quickEntryText"), "Coffee 12")
    }
    func testInterruptedImportNeverMarksPartialDataReady() throws {
        let repository = try LocalTestData.repository(imported: false)
        let snapshot = SyncSnapshot(workspaceId: UUID(), generation: 1, cursor: "5", records: [SyncRecord(entity: "account", key: UUID().uuidString, version: "5", data: ["name": .string("Incomplete")])])
        XCTAssertThrowsError(try repository.importSnapshot(snapshot)); XCTAssertFalse(repository.snapshot.imported)
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        XCTAssertFalse(reopened.snapshot.imported); XCTAssertTrue(reopened.snapshot.accounts.isEmpty)
        try reopened.importSnapshot(SyncSnapshot(workspaceId: snapshot.workspaceId, generation: 1, cursor: "5", records: []))
        XCTAssertTrue(reopened.snapshot.imported)
    }
    func testCategoryHistoryAndRelationshipChangesUseUnsyncedLocalRows() async throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        let category = try await store.createCategory(name: "Food", kind: .expense, icon: "label", color: .coral)
        let created = try await store.createTransaction(LocalTestData.transaction(account.id, categoryID: category.id, occurredAt: .now))
        let updated = try await store.updateCategory(category, name: "Dining", parentID: nil, icon: "star", color: .purple)
        XCTAssertEqual(store.allTransactions.first?.category?.name, "Dining")
        let suggestions = try await store.categorySuggestions(description: "Morning", kind: .expense)
        XCTAssertEqual(suggestions.first?.categoryId, updated.id)
        try await store.deleteCategory(updated)
        XCTAssertNil(repository.snapshot.transactions[created.id]?.categoryId)
    }
    func testGlobalBudgetsKeepAccountsSeparateAndSurviveReopening() async throws {
        let repository = try LocalTestData.repository()
        let first = try LocalTestData.account(repository)
        let second = try LocalTestData.account(repository, name: "Second")
        let store = BudgetStore(repository: repository)
        for (id, limit) in [(first.id, "100"), (first.id, "200"), (second.id, "300"), (nil, "500")] as [(UUID?, String)] {
            _ = try await store.saveBudget(MonthlyBudgetRequest(accountId: id, currency: "USD", monthlyLimit: limit, groups: [], categoryAssignments: []))
        }
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        let budgets = BudgetStore(repository: reopened)
        XCTAssertEqual(budgets.budget(accountID: first.id)?.monthlyLimit, "200")
        XCTAssertEqual(budgets.budget(accountID: second.id)?.monthlyLimit, "300")
        XCTAssertEqual(budgets.budget(accountID: nil)?.monthlyLimit, "500")
        XCTAssertEqual(budgets.budgets.count, 3)
        XCTAssertEqual(budgets.state, .loaded)
        _ = try await budgets.saveBudget(MonthlyBudgetRequest(accountId: first.id, currency: "USD", monthlyLimit: nil, groups: [], categoryAssignments: []))
        XCTAssertNil(budgets.budget(accountID: first.id))
        XCTAssertEqual(budgets.budget(accountID: second.id)?.monthlyLimit, "300")
        XCTAssertEqual(budgets.budget(accountID: nil)?.monthlyLimit, "500")
    }
    func testLegacyBudgetMigrationKeepsLatestSetupAndAccountScopes() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("budget-migration-\(UUID()).sqlite").path
        let legacy = try LocalDatabase(path: path)
        let accountID = UUID()
        let groupID = UUID()
        let categoryID = UUID()
        func budget(id: UUID = UUID(), account: UUID?, limit: String, updated: Date) -> MonthlyBudget {
            MonthlyBudget(id: id, accountId: account, currency: "USD", monthlyLimit: limit,
                groups: [BudgetGroup(id: groupID, name: "Needs", limit: "200", sortOrder: 0)],
                categoryAssignments: [BudgetCategoryAssignment(categoryId: categoryID, groupId: groupID, limit: "75")],
                createdAt: LocalTestData.now, updatedAt: updated)
        }
        let latest = budget(account: accountID, limit: "500", updated: LocalTestData.now.addingTimeInterval(100))
        let older = budget(account: accountID, limit: "100", updated: LocalTestData.now)
        let all = budget(account: nil, limit: "900", updated: LocalTestData.now)
        try legacy.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier='global-budgets-v2'")
            for (value, month) in [(latest, "2025-12"), (older, "2026-01"), (all, "2026-01")] {
                var data = try LocalJSON.object(value)
                data["month"] = .string(month)
                try storeLocalRecord(entity: "budget", key: "\(budgetKey(accountID: value.accountId)):\(month)", data: data, db: db)
            }
            try setMetadata(true, "imported", db: db)
        }
        let repository = try LocalFinanceRepository(path: path)
        XCTAssertEqual(repository.snapshot.budgets.count, 2)
        XCTAssertEqual(repository.snapshot.budgets[budgetKey(accountID: accountID)], latest)
        XCTAssertEqual(repository.snapshot.budgets["all"], all)
        let stored = try XCTUnwrap(repository.localVersion(entity: "budget", key: budgetKey(accountID: accountID)))
        XCTAssertNil(stored["month"])
        XCTAssertEqual(try LocalFinanceRepository(path: path).snapshot.budgets, repository.snapshot.budgets)
    }

    func testBudgetMigrationPreservesPendingEditsAndRebasesTheirDependencies() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("budget-outbox-migration-\(UUID()).sqlite").path
        let legacy = try LocalDatabase(path: path)
        let workspaceID = UUID()
        let clientID = UUID()
        let first = MonthlyBudget(id: UUID(), accountId: nil, currency: "USD", monthlyLimit: "100", groups: [], categoryAssignments: [], createdAt: LocalTestData.now, updatedAt: LocalTestData.now)
        let latest = MonthlyBudget(id: UUID(), accountId: nil, currency: "USD", monthlyLimit: "250", groups: [], categoryAssignments: [], createdAt: LocalTestData.now, updatedAt: LocalTestData.now.addingTimeInterval(100))
        let ids = [UUID(), UUID()]
        try legacy.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier='global-budgets-v2'")
            for (index, value) in [first, latest].enumerated() {
                let month = index == 0 ? "2026-01" : "2026-02"
                var data = try LocalJSON.object(value)
                data["month"] = .string(month)
                let change = SyncChange(entity: "budget", key: "all:\(month)", baseVersion: "1", data: data)
                try storeLocalRecord(entity: "budget", key: change.key, data: data, db: db)
                let mutation = SyncMutation(clientId: clientID, mutationId: ids[index], generation: 1, authoredAt: value.updatedAt, changes: [change], reset: false, workspaceId: workspaceID)
                try storeOutbox(PendingMutation(mutation: mutation, dependencies: [], attempts: 1, nextAttempt: .now, sent: true, issue: nil), db: db)
            }
            try setMetadata(true, "imported", db: db)
            try setMetadata(workspaceID, "workspaceID", db: db)
        }
        let repository = try LocalFinanceRepository(path: path)
        let queue = repository.snapshot.pending
        XCTAssertEqual(repository.snapshot.budgets["all"], latest)
        XCTAssertEqual(queue.count, 2)
        XCTAssertTrue(queue.allSatisfy { !ids.contains($0.id) && !$0.sent })
        XCTAssertTrue(queue.allSatisfy { $0.mutation.changes[0].key == "all" && $0.mutation.changes[0].data?["month"] == nil && $0.mutation.changes[0].baseVersion == nil })
        XCTAssertEqual(queue[1].dependencies, [queue[0].id])
        // A server budget from before the migration stays separate from our offline edits.
        let server = SyncRecord(entity: "budget", key: "all", version: "20", data: try LocalJSON.object(first))
        try repository.acknowledge(SyncResult(mutationId: queue[0].id, status: "conflict", generation: 1, records: [server], message: "Review budget"), for: queue[0])
        XCTAssertEqual(repository.snapshot.budgets["all"], latest)
        try repository.resolve(queue[0].id, keepLocal: true)
        let replacement = try XCTUnwrap(repository.snapshot.pending.first)
        XCTAssertEqual(repository.snapshot.pending.count, 1)
        XCTAssertEqual(replacement.mutation.changes[0].baseVersion, "20")
        XCTAssertEqual(replacement.mutation.changes[0].data?["monthlyLimit"], .string("250"))
        try repository.acknowledge(LocalTestData.ack(replacement, version: "21"), for: replacement)
        XCTAssertEqual(try LocalFinanceRepository(path: path).snapshot.budgets["all"], latest)
        XCTAssertTrue(repository.snapshot.pending.isEmpty)
    }

    func testRetiredMonthlySyncRecordsCannotRestoreClearedGlobalBudget() throws {
        let repository = try LocalTestData.repository()
        let workspaceID = try XCTUnwrap(repository.value(UUID.self, key: "workspaceID"))
        let budget = MonthlyBudget(id: UUID(), accountId: nil, currency: "USD", monthlyLimit: "500", groups: [], categoryAssignments: [], createdAt: LocalTestData.now, updatedAt: LocalTestData.now)
        var old = try LocalJSON.object(budget)
        old["month"] = .string("2026-01")
        try repository.receive(SyncSnapshot(workspaceId: workspaceID, generation: 1, cursor: "5", records: [
            SyncRecord(entity: "budget", key: "all:2026-01", version: "2", data: old),
            SyncRecord(entity: "budget", key: "all", version: "4", data: try LocalJSON.object(budget)),
            SyncRecord(entity: "budget", key: "all", version: "5", data: nil)
        ]))
        XCTAssertTrue(repository.snapshot.budgets.isEmpty)
    }

    func testOlderAcknowledgmentCannotOverwriteANewerLocalEdit() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        let create = repository.snapshot.pending[0]; try repository.markSent(create)
        _ = try repository.edit { try $0.saveAccount(id: account.id, name: "New name", type: account.type, currency: account.currency, icon: account.icon, color: account.iconColor) }
        let latestID = repository.snapshot.pending.last!.id
        try repository.acknowledge(LocalTestData.ack(create, version: "10"), for: create)
        XCTAssertEqual(repository.snapshot.accounts[account.id]?.name, "New name")
        XCTAssertEqual(repository.snapshot.pending.first?.id, latestID)
        XCTAssertEqual(repository.snapshot.pending.first?.mutation.changes.first?.baseVersion, "10")
        XCTAssertTrue(repository.snapshot.pending.first!.dependencies.isEmpty)
    }
    func testIncomingPagesProtectPendingWorkAndAdvanceCursorAtomically() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        let pending = repository.snapshot.pending[0]; let workspace = try XCTUnwrap(repository.value(UUID.self, key: "workspaceID"))
        var server = pending.mutation.changes[0].data!; server["name"] = .string("Server")
        try repository.receive(SyncSnapshot(workspaceId: workspace, generation: 1, cursor: "8", records: [SyncRecord(entity: "account", key: account.id.uuidString.lowercased(), version: "8", data: server)]))
        XCTAssertEqual(repository.snapshot.accounts[account.id]?.name, "Main"); XCTAssertEqual(try repository.value(String.self, key: "cursor"), "8")
        let invalid = SyncSnapshot(workspaceId: workspace, generation: 1, cursor: "9", records: [SyncRecord(entity: "transaction", key: UUID().uuidString, version: "9", data: [:])])
        XCTAssertThrowsError(try repository.receive(invalid)); XCTAssertEqual(try repository.value(String.self, key: "cursor"), "8")
    }
    func testReviewKeepsLocalOrRestoresServerAndReleasesDependents() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository); let pending = repository.snapshot.pending[0]
        var server = pending.mutation.changes[0].data!; server["name"] = .string("Remote")
        let conflict = SyncResult(mutationId: pending.id, status: "conflict", generation: 1, records: [SyncRecord(entity: "account", key: account.id.uuidString.lowercased(), version: "20", data: server)], message: "Changed elsewhere")
        try repository.acknowledge(conflict, for: pending)
        XCTAssertNotNil(repository.snapshot.pending.first?.issue); XCTAssertEqual(repository.snapshot.accounts[account.id]?.name, "Main")
        try repository.resolve(pending.id, keepLocal: true)
        let replacement = repository.snapshot.pending[0]
        XCTAssertNotEqual(replacement.id, pending.id); XCTAssertEqual(replacement.mutation.changes[0].baseVersion, "20"); XCTAssertNil(replacement.issue)
        try repository.resolve(replacement.id, keepLocal: false)
        XCTAssertEqual(repository.snapshot.accounts[account.id]?.name, "Remote"); XCTAssertTrue(repository.snapshot.pending.isEmpty)
    }
    func testOfflineResetIgnoresInflightAcknowledgmentsAndRebasesNewWork() throws {
        let repository = try LocalTestData.repository(); _ = try LocalTestData.account(repository); let old = repository.snapshot.pending[0]
        try repository.markSent(old); try repository.deleteAllData()
        let reset = repository.snapshot.pending[0]
        let new = try LocalTestData.account(repository, name: "After reset")
        try repository.acknowledge(LocalTestData.ack(old, version: "20"), for: old)
        XCTAssertEqual(repository.snapshot.accounts.count, 1); XCTAssertNotNil(repository.snapshot.accounts[new.id])
        try repository.acknowledge(SyncResult(mutationId: reset.id, status: "accepted", generation: 2, records: [], message: nil), for: reset)
        XCTAssertEqual(repository.snapshot.pending.first?.mutation.generation, 2)
        XCTAssertTrue(repository.snapshot.pending.first!.dependencies.isEmpty)
        XCTAssertEqual(try repository.value(Bool.self, key: "pendingReset"), false)
    }
    func testRepeatedResetKeepsInflightResetIdentity() throws {
        let repository = try LocalTestData.repository(); try repository.deleteAllData(); let reset = repository.snapshot.pending[0]
        try repository.markSent(reset); _ = try LocalTestData.account(repository); try repository.deleteAllData()
        XCTAssertEqual(repository.snapshot.pending.map(\.id), [reset.id]); XCTAssertTrue(repository.snapshot.pending[0].sent)
    }
    func testRemoteResetRequiresOneExplicitDecisionAndPreservesLocalWork() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        let remote = SyncSnapshot(workspaceId: try XCTUnwrap(repository.value(UUID.self, key: "workspaceID")), generation: 2, cursor: "50", records: [])
        try repository.receiveWorkspaceReset(remote)
        XCTAssertNotNil(repository.snapshot.accounts[account.id]); XCTAssertNotNil(repository.snapshot.pending[0].issue)
        try repository.resolveWorkspaceReset(keepLocal: true)
        XCTAssertNotNil(repository.snapshot.accounts[account.id]); XCTAssertEqual(repository.snapshot.pending[0].mutation.generation, 2)
        XCTAssertNil(try repository.value(SyncSnapshot.self, key: "remoteReset"))
    }
    func testReviewedBatchCommitsOfflineAndClearsDraftInTheSameCommit() async throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        func draft(_ amount: String) -> QuickEntryDraft {
            QuickEntryDraft(payload: QuickEntryDraftPayload(id: UUID(), kind: .expense, accountId: account.id, destinationAccountId: nil, amount: amount, currency: "USD", categoryId: nil, merchant: "Coffee", payee: nil, note: nil, occurredAt: LocalTestData.now, recurrence: nil, sourceText: "Coffee", conversion: nil, warnings: []), category: nil)
        }
        let review = QuickEntryReviewPresentation(prompt: "Coffee and lunch", drafts: [draft("4.25"), draft("12.1250")], unparsedText: [])
        try repository.saveValue(review, key: "quickEntryReview"); try repository.saveValue(review.prompt, key: "quickEntryText")
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        let store = TransactionStore(repository: reopened)
        XCTAssertEqual(store.savedQuickEntryReview()?.drafts.count, 2)
        let saved = try await store.commitQuickEntryDrafts(review.drafts)
        XCTAssertEqual(saved, 2); XCTAssertEqual(store.allTransactions.count, 2)
        XCTAssertEqual(reopened.snapshot.pending.last?.mutation.changes.count, 2)
        XCTAssertNil(store.savedQuickEntryReview()); XCTAssertEqual(store.savedQuickEntryText(), "")
        let broken = QuickEntryReviewPresentation(prompt: "Invalid draft", drafts: [draft("4"), draft("0")], unparsedText: [])
        try store.saveQuickEntryReview(broken)
        let count = reopened.snapshot.pending.count
        do { _ = try await store.commitQuickEntryDrafts(broken.drafts); XCTFail("The whole batch must fail validation") } catch {}
        XCTAssertEqual(store.allTransactions.count, 2); XCTAssertEqual(reopened.snapshot.pending.count, count)
        XCTAssertEqual(store.savedQuickEntryReview()?.prompt, "Invalid draft")
    }
    func testReviewUsesLaterLocalFixesAndCoalescesTheirDependentOperations() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository); let first = repository.snapshot.pending[0]
        try repository.acknowledge(SyncResult(mutationId: first.id, status: "rejected", generation: 1, records: [], message: "Please review"), for: first)
        _ = try repository.edit { try $0.saveAccount(id: account.id, name: "Corrected", type: account.type, currency: account.currency, icon: account.icon, color: account.iconColor) }
        _ = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id)) }
        try repository.resolve(first.id, keepLocal: true)
        XCTAssertEqual(repository.snapshot.pending.count, 1)
        let retried = repository.snapshot.pending[0]
        XCTAssertEqual(retried.mutation.changes.first { $0.entity == "account" }?.data?["name"]?.string, "Corrected")
        XCTAssertEqual(retried.mutation.changes.filter { $0.entity == "transaction" }.count, 1)
        XCTAssertTrue(retried.dependencies.isEmpty); XCTAssertNil(retried.issue)
    }
    func testRetryStateSurvivesRelaunchWithoutChangingFinanceLoadingState() async throws {
        let repository = try LocalTestData.repository(); _ = try LocalTestData.account(repository); let pending = repository.snapshot.pending[0]
        try repository.markSent(pending); try repository.recordFailure(pending, now: LocalTestData.now)
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        XCTAssertEqual(reopened.snapshot.pending[0].attempts, 1); XCTAssertTrue(reopened.snapshot.pending[0].sent)
        XCTAssertGreaterThan(reopened.snapshot.pending[0].nextAttempt, LocalTestData.now)
        let store = TransactionStore(repository: reopened); await store.loadTransactions(accountID: nil)
        XCTAssertEqual(store.state, .loaded); XCTAssertEqual(store.upcomingState, .loaded); XCTAssertFalse(store.isLoadingCategories)
    }
}
