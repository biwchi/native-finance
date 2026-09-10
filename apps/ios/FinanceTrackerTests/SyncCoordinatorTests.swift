import XCTest
@testable import FinanceTracker

actor TestSyncServer: SyncTransport {
    let workspace = UUID()
    var records: [String: SyncRecord] = [:]
    var receipts: [UUID: SyncResult] = [:]
    var version = 0
    var calls = 0
    var offline = false
    var loseNextResponse = false
    var holdNext = false
    var held: CheckedContinuation<Void, Never>?
    var pushWaiter: CheckedContinuation<Void, Never>?
    func configure(offline: Bool = false, loseResponse: Bool = false, hold: Bool = false) { self.offline = offline; loseNextResponse = loseResponse; holdNext = hold }
    func syncBootstrap() async throws -> SyncSnapshot { snapshot() }
    func syncChanges(cursor: String, generation: Int) async throws -> SyncSnapshot {
        if offline { throw URLError(.notConnectedToInternet) }; return snapshot()
    }
    func syncPush(_ mutation: SyncMutation) async throws -> SyncResult {
        calls += 1
        if holdNext {
            holdNext = false
            await withCheckedContinuation { continuation in held = continuation; pushWaiter?.resume(); pushWaiter = nil }
        }
        if offline { throw URLError(.notConnectedToInternet) }
        if let receipt = receipts[mutation.mutationId] { return receipt }
        version += 1
        let changed = mutation.changes.map { SyncRecord(entity: $0.entity, key: $0.key, version: String(version), data: $0.data) }
        for record in changed { records[record.identity] = record }
        let response = SyncResult(mutationId: mutation.mutationId, status: "accepted", generation: 1, records: changed, message: nil)
        receipts[mutation.mutationId] = response
        if loseNextResponse { loseNextResponse = false; throw URLError(.networkConnectionLost) }
        return response
    }
    func waitForHeldPush() async { if held != nil { return }; await withCheckedContinuation { pushWaiter = $0 } }
    func release() { held?.resume(); held = nil }
    private func snapshot() -> SyncSnapshot { SyncSnapshot(workspaceId: workspace, generation: 1, cursor: String(version), records: Array(records.values), hasMore: false, reset: false) }
}

@MainActor
final class SyncCoordinatorTests: XCTestCase {
    func testLocalCommitImmediatelyStartsOneWorkerWithoutWaitingForServer() async throws {
        let server = TestSyncServer(); let repository = try LocalTestData.repository(imported: false)
        try repository.importSnapshot(try await server.syncBootstrap()); await server.configure(hold: true)
        let worker = SyncCoordinator(repository: repository, transport: server)
        let account = try LocalTestData.account(repository)
        await server.waitForHeldPush()
        XCTAssertNotNil(repository.snapshot.accounts[account.id])
        XCTAssertEqual(repository.snapshot.pending.count, 1)
        await server.release(); await worker.waitUntilIdle()
        XCTAssertTrue(repository.snapshot.pending.isEmpty)
        let count = await server.calls; XCTAssertEqual(count, 1); worker.cancel()
    }
    func testConsecutiveEditsDuringAnUploadRetainLatestValuesAndSendInOrder() async throws {
        let server = TestSyncServer(); let repository = try LocalTestData.repository(imported: false)
        try repository.importSnapshot(try await server.syncBootstrap()); await server.configure(hold: true)
        let worker = SyncCoordinator(repository: repository, transport: server)
        let account = try LocalTestData.account(repository)
        await server.waitForHeldPush()
        _ = try repository.edit { try $0.saveAccount(id: account.id, name: "Edited during upload", type: .checking, currency: "USD", icon: "wallet", color: .blue) }
        XCTAssertEqual(repository.snapshot.accounts[account.id]?.name, "Edited during upload")
        await server.release(); await worker.waitUntilIdle()
        XCTAssertTrue(repository.snapshot.pending.isEmpty)
        XCTAssertEqual(repository.snapshot.accounts[account.id]?.name, "Edited during upload")
        let stored = await server.records; XCTAssertEqual(stored["account:\(account.id.uuidString.lowercased())"]?.data?["name"]?.string, "Edited during upload")
        let count = await server.calls; XCTAssertEqual(count, 2); worker.cancel()
    }
    func testLostResponseRetriesTheSameMutationAfterRelaunch() async throws {
        let server = TestSyncServer(); let repository = try LocalTestData.repository(imported: false)
        try repository.importSnapshot(try await server.syncBootstrap()); await server.configure(loseResponse: true)
        let worker = SyncCoordinator(repository: repository, transport: server)
        _ = try LocalTestData.account(repository); await worker.waitUntilIdle(); worker.cancel()
        let mutationID = repository.snapshot.pending[0].id
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        try reopened.requireDatabase().write { try $0.execute(sql: "UPDATE outbox SET nextAttempt=0"); try bumpLocalRevision($0) }; try reopened.reload()
        let retry = SyncCoordinator(repository: reopened, transport: server); retry.requestSync(); await retry.waitUntilIdle()
        XCTAssertTrue(reopened.snapshot.pending.isEmpty)
        let receipts = await server.receipts; XCTAssertEqual(Set(receipts.keys), [mutationID]); XCTAssertEqual(reopened.snapshot.accounts.count, 1); retry.cancel()
    }
    func testOfflineAndSlowSyncNeverChangeLocalScreenState() async throws {
        let server = TestSyncServer(); let repository = try LocalTestData.repository(imported: false)
        try repository.importSnapshot(try await server.syncBootstrap()); await server.configure(offline: true)
        let worker = SyncCoordinator(repository: repository, transport: server)
        let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        _ = try await store.createTransaction(LocalTestData.transaction(account.id)); await worker.waitUntilIdle()
        XCTAssertEqual(store.state, .loaded); XCTAssertEqual(store.upcomingState, .loaded)
        XCTAssertEqual(store.allTransactions.count, 1); XCTAssertEqual(repository.snapshot.pending.count, 2)
        XCTAssertFalse(AccountStore(repository: repository).isLoading)
        XCTAssertFalse(worker.isImporting); XCTAssertNil(worker.setupError); worker.cancel()
    }
}
