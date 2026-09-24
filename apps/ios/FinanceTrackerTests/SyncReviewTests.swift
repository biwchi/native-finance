import XCTest
import GRDB
import SwiftUI
import UIKit
@testable import FinanceTracker

@MainActor
final class SyncReviewTests: XCTestCase {
    private func remote(_ repository: LocalFinanceRepository, records: [SyncRecord] = [], cursor: String = "20") throws -> SyncSnapshot {
        SyncSnapshot(workspaceId: try XCTUnwrap(repository.value(UUID.self, key: "workspaceID")), generation: 1, cursor: cursor, records: records, hasMore: false, reset: false)
    }
    private func syncedAccount(_ repository: LocalFinanceRepository) throws -> Account {
        let account = try LocalTestData.account(repository)
        let pending = try XCTUnwrap(repository.snapshot.pending.first)
        try repository.acknowledge(LocalTestData.ack(pending), for: pending)
        return account
    }
    private func reject(_ repository: LocalFinanceRepository, _ pending: PendingMutation) throws {
        try repository.markSent(pending)
        try repository.acknowledge(SyncResult(mutationId: pending.id, status: "rejected", generation: 1, records: [], message: "The referenced account no longer exists"), for: pending)
    }

    func testRejectedCreateThenExplicitDeleteClearsOnlyAfterCompleteSnapshot() throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        let transaction = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id)) }
        let creation = try XCTUnwrap(repository.snapshot.pending.first); try reject(repository, creation)
        try repository.edit { $0.erase("transaction", key: transaction.id.uuidString) }
        XCTAssertEqual(repository.snapshot.pending.count, 2)
        XCTAssertTrue(try repository.needsSyncReviewRefresh)
        XCTAssertTrue(try repository.reconcileCompletedChanges(with: remote(repository)))
        XCTAssertTrue(repository.snapshot.pending.isEmpty)
        XCTAssertTrue(repository.snapshot.transactions.isEmpty)
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        XCTAssertTrue(reopened.snapshot.pending.isEmpty)
    }

    func testLiveUnsyncedTransactionSurvivesAccountDeletionAndCanBeExported() throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        let transaction = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id, amount: "27.1256")) }
        try reject(repository, XCTUnwrap(repository.snapshot.pending.first))
        let deletion = SyncRecord(entity: "account", key: account.id.uuidString.lowercased(), version: "20", data: nil)
        XCTAssertFalse(try repository.reconcileCompletedChanges(with: remote(repository, records: [deletion])))
        XCTAssertEqual(repository.snapshot.transactions[transaction.id]?.amount, "27.1256")
        XCTAssertEqual(repository.snapshot.pending.count, 1)
        let review = try XCTUnwrap(repository.syncReviewItems().first)
        XCTAssertTrue(review.hasMissingReference)
        XCTAssertEqual(review.rows.first?.syncedAbsence, "Not saved on other devices")
        let data = try repository.exportSyncReview(review.id)
        let exported = try JSONDecoder().decode([String: JSONValue].self, from: data)
        guard case .array(let entries) = exported["savedEntries"], case .object(let entry) = entries.first,
              case .object(let local) = entry["local"] else { return XCTFail("The export must contain the saved transaction") }
        XCTAssertEqual(local["amount"]?.string, "27.1256")
        XCTAssertNotNil(exported["originalChanges"])
        XCTAssertFalse(try repository.needsSyncReviewRefresh)
    }

    func testMissingCachedCopyIsNotPresentedAsDeletion() throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        _ = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id)) }
        try reject(repository, XCTUnwrap(repository.snapshot.pending.first))
        let row = try XCTUnwrap(repository.syncReviewItems().first?.rows.first)
        XCTAssertEqual(row.syncedAbsence, "No synced copy available yet")
        XCTAssertEqual(row.title, "Coffee")
        XCTAssertNotNil(row.local)
    }

    func testDeletionAgainstKnownTombstoneCompletesWithoutReview() throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        try repository.edit { $0.deleteAccount(account.id) }
        let deletion = try XCTUnwrap(repository.snapshot.pending.first)
        try reject(repository, deletion)
        XCTAssertTrue(try repository.reconcileCompletedChanges(with: remote(repository, records: [
            SyncRecord(entity: "account", key: account.id.uuidString.lowercased(), version: "20", data: nil)
        ])))
        XCTAssertTrue(repository.snapshot.pending.isEmpty)
    }

    func testServerEntryStillExistsSoDeletionNeedsToBeSentOrReviewed() throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        let data = try LocalJSON.object(account)
        try repository.edit { $0.deleteAccount(account.id) }
        try reject(repository, XCTUnwrap(repository.snapshot.pending.first))
        XCTAssertFalse(try repository.reconcileCompletedChanges(with: remote(repository, records: [
            SyncRecord(entity: "account", key: account.id.uuidString.lowercased(), version: "20", data: data)
        ])))
        XCTAssertEqual(repository.snapshot.pending.count, 1)
        XCTAssertTrue(try XCTUnwrap(repository.syncReviewItems().first).hasKnownDifference)
    }

    func testEmptyLocalRowWithoutQueuedDeletionDoesNotAuthorizeDiscard() throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        let transaction = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id)) }
        try reject(repository, XCTUnwrap(repository.snapshot.pending.first))
        // Simulate a legacy inconsistency. The outbox still contains the only saved copy.
        try repository.requireDatabase().write { db in
            try storeLocalRecord(entity: "transaction", key: transaction.id.uuidString.lowercased(), data: nil, db: db)
        }
        XCTAssertFalse(try repository.reconcileCompletedChanges(with: remote(repository)))
        XCTAssertEqual(repository.snapshot.pending.count, 1)
        XCTAssertNotNil(repository.snapshot.pending[0].mutation.changes[0].data)
        let review = try XCTUnwrap(repository.syncReviewItems().first)
        XCTAssertEqual(review.rows.first?.savedData?["amount"]?.string, "12.3456")
        try repository.resolve(review.id, keepLocal: true)
        XCTAssertEqual(repository.snapshot.transactions[transaction.id]?.amount, "12.3456")
    }

    func testDeletedRecurringCreationDropsOnlyObsoleteExclusions() throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        let transaction = try repository.edit(now: LocalTestData.now) {
            try $0.saveTransaction(request: LocalTestData.transaction(account.id, recurrence: RecurrenceRequest(frequency: .monthly, endAt: nil)))
        }
        let scheduleID = try XCTUnwrap(repository.snapshot.transactions[transaction.id]?.recurringScheduleId)
        try reject(repository, XCTUnwrap(repository.snapshot.pending.first))
        try repository.edit(now: LocalTestData.now) {
            try $0.deleteOccurrence(scheduleID: scheduleID, date: transaction.occurredAt, action: .occurrenceAndFuture, recordedID: transaction.id)
        }
        XCTAssertFalse(repository.snapshot.exclusions.isEmpty)
        XCTAssertTrue(try repository.reconcileCompletedChanges(with: remote(repository)))
        XCTAssertTrue(repository.snapshot.pending.isEmpty)
        XCTAssertTrue(repository.snapshot.transactions.isEmpty)
        XCTAssertTrue(repository.snapshot.schedules.isEmpty)
        XCTAssertTrue(repository.snapshot.exclusions.isEmpty)
    }

    func testRecurrenceActionCannotBeDiscardedWhileScheduleStillExists() throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        let transaction = try repository.edit(now: LocalTestData.now) {
            try $0.saveTransaction(request: LocalTestData.transaction(account.id, recurrence: RecurrenceRequest(frequency: .monthly, endAt: nil)))
        }
        let creation = try XCTUnwrap(repository.snapshot.pending.first)
        let schedule = try XCTUnwrap(creation.mutation.changes.first { $0.entity == "schedule" })
        try reject(repository, creation)
        try repository.edit(now: LocalTestData.now) {
            try $0.deleteOccurrence(scheduleID: XCTUnwrap(repository.snapshot.transactions[transaction.id]?.recurringScheduleId), date: transaction.occurredAt, action: .occurrenceAndFuture, recordedID: transaction.id)
        }
        XCTAssertFalse(try repository.reconcileCompletedChanges(with: remote(repository, records: [
            SyncRecord(entity: schedule.entity, key: schedule.key, version: "20", data: schedule.data)
        ])))
        XCTAssertEqual(repository.snapshot.pending.count, 2)
    }

    func testDependentLiveEntriesAreIncludedInReviewAndPreventAutomaticDiscard() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        try reject(repository, XCTUnwrap(repository.snapshot.pending.first))
        let transaction = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id)) }
        try repository.edit { $0.erase("account", key: account.id.uuidString) }
        XCTAssertFalse(try repository.reconcileCompletedChanges(with: remote(repository)))
        let item = try XCTUnwrap(repository.syncReviewItems().first)
        XCTAssertEqual(item.operationCount, 3)
        XCTAssertEqual(item.rows.map(\.key), [transaction.id.uuidString.lowercased()])
        XCTAssertEqual(repository.snapshot.transactions.count, 1)
    }

    func testUncertainSentDependentKeepsItsReceiptIdentity() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        try reject(repository, XCTUnwrap(repository.snapshot.pending.first))
        try repository.edit { $0.deleteAccount(account.id) }
        let deletion = try XCTUnwrap(repository.snapshot.pending.last)
        try repository.markSent(deletion)
        XCTAssertFalse(try repository.reconcileCompletedChanges(with: remote(repository)))
        XCTAssertEqual(repository.snapshot.pending.last?.id, deletion.id)
        XCTAssertEqual(repository.snapshot.pending.last?.sent, true)
    }

    func testIncompleteStaleOrDifferentGenerationSnapshotCannotClearWork() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        try reject(repository, XCTUnwrap(repository.snapshot.pending.first))
        try repository.edit { $0.deleteAccount(account.id) }
        let workspace = try XCTUnwrap(repository.value(UUID.self, key: "workspaceID"))
        for snapshot in [
            SyncSnapshot(workspaceId: workspace, generation: 1, cursor: "20", records: [], hasMore: true),
            SyncSnapshot(workspaceId: workspace, generation: 2, cursor: "20", records: []),
            SyncSnapshot(workspaceId: UUID(), generation: 1, cursor: "20", records: [])
        ] { XCTAssertFalse(try repository.reconcileCompletedChanges(with: snapshot)) }
        try repository.saveValue("30", key: "cursor")
        XCTAssertFalse(try repository.reconcileCompletedChanges(with: remote(repository)))
        XCTAssertEqual(repository.snapshot.pending.count, 2)
    }

    func testSharedDependentIsReviewedOnceAndDecisionCoversBothRoots() throws {
        let repository = try LocalTestData.repository()
        let a = try LocalTestData.account(repository); let b = try LocalTestData.account(repository)
        for item in repository.snapshot.pending { try reject(repository, item) }
        try repository.edit { editor in
            _ = try editor.saveTransaction(request: LocalTestData.transaction(a.id))
            _ = try editor.saveTransaction(request: LocalTestData.transaction(b.id, kind: .income))
        }
        let items = try repository.syncReviewItems()
        XCTAssertEqual(items.count, 1); XCTAssertEqual(items[0].operationCount, 3)
        XCTAssertEqual(items[0].rows.count, 4)
        try repository.resolve(items[0].id, keepLocal: true)
        XCTAssertEqual(repository.snapshot.pending.count, 1)
        XCTAssertEqual(repository.snapshot.pending[0].mutation.changes.count, 4)
        XCTAssertTrue(repository.snapshot.pending[0].dependencies.isEmpty)
    }

    func testReadFailureDoesNotBecomeADeletedComparison() throws {
        let repository = try LocalTestData.repository(); let account = try LocalTestData.account(repository)
        try reject(repository, XCTUnwrap(repository.snapshot.pending.first))
        try repository.requireDatabase().write {
            try $0.execute(sql: "UPDATE records SET serverData=? WHERE key=?", arguments: [Data("broken".utf8), account.id.uuidString.lowercased()])
        }
        XCTAssertThrowsError(try repository.syncReviewItems())
        XCTAssertEqual(repository.snapshot.pending.count, 1)
    }

    func testWorkerRefreshesAndFinishesSupersededCreatesWithoutAUserDecision() async throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        let transaction = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id)) }
        try repository.edit { $0.erase("transaction", key: transaction.id.uuidString) }
        let server = ReviewTestServer(snapshot: try remote(repository))
        let worker = SyncCoordinator(repository: repository, transport: server)
        worker.requestSync(); await worker.waitUntilIdle(); worker.cancel()
        XCTAssertTrue(repository.snapshot.pending.isEmpty)
        let refreshes = await server.refreshes
        XCTAssertEqual(refreshes, 1)
    }

    func testWorkerPreservesWorkWhenAuthoritativeRefreshFails() async throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        let transaction = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id)) }
        try repository.edit { $0.erase("transaction", key: transaction.id.uuidString) }
        let server = ReviewTestServer(snapshot: try remote(repository), failsRefresh: true)
        let worker = SyncCoordinator(repository: repository, transport: server)
        worker.requestSync(); await worker.waitUntilIdle(); worker.cancel()
        XCTAssertEqual(repository.snapshot.pending.count, 2)
        XCTAssertTrue(try repository.needsSyncReviewRefresh)
    }

    func testUnchangedUnresolvedWorkDoesNotRepeatedlyDownloadTheWholeLedger() async throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        _ = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id)) }
        let server = ReviewTestServer(snapshot: try remote(repository))
        let worker = SyncCoordinator(repository: repository, transport: server)
        worker.requestSync(); await worker.waitUntilIdle()
        worker.requestSync(); await worker.waitUntilIdle(); worker.cancel()
        let refreshes = await server.refreshes
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(repository.snapshot.transactions.count, 1)
        XCTAssertEqual(repository.snapshot.pending.count, 1)
    }

    func testSavedEntryReviewRendersInLightAndDarkMode() async throws {
        let repository = try LocalTestData.repository(); let account = try syncedAccount(repository)
        _ = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id, amount: "27.1256")) }
        try reject(repository, XCTUnwrap(repository.snapshot.pending.first))
        _ = try repository.reconcileCompletedChanges(with: remote(repository, records: [
            SyncRecord(entity: "account", key: account.id.uuidString.lowercased(), version: "20", data: nil)
        ]))
        for scheme in [ColorScheme.light, .dark] {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let controller = UIHostingController(rootView: NavigationStack { SyncReviewView(repository: repository) }.preferredColorScheme(scheme))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller; window.makeKeyAndVisible()
            defer { window.isHidden = true }
            controller.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(500))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Saved-entry-review-\(scheme)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}

private actor ReviewTestServer: SyncTransport {
    let snapshot: SyncSnapshot
    let failsRefresh: Bool
    var refreshes = 0
    init(snapshot: SyncSnapshot, failsRefresh: Bool = false) { self.snapshot = snapshot; self.failsRefresh = failsRefresh }
    func syncBootstrap() async throws -> SyncSnapshot {
        refreshes += 1
        if failsRefresh { throw URLError(.notConnectedToInternet) }
        return snapshot
    }
    func syncChanges(cursor: String, generation: Int) async throws -> SyncSnapshot { snapshot }
    func syncPush(_ mutation: SyncMutation) async throws -> SyncResult {
        SyncResult(mutationId: mutation.mutationId, status: "rejected", generation: snapshot.generation, records: [], message: "The referenced account no longer exists")
    }
}
