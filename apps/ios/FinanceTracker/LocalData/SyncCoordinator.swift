import Foundation
import Combine
import Network
import BackgroundTasks
import UIKit

@MainActor
final class SyncCoordinator: ObservableObject {
    static let backgroundIdentifier = "com.financetracker.sync"
    static let shared = SyncCoordinator(repository: .shared, transport: APIClient())
    @Published private(set) var isImporting = false
    @Published private(set) var setupError: String?
    private let repository: LocalFinanceRepository
    private let transport: any SyncTransport
    private var worker: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var foregroundTimer: Task<Void, Never>?
    private var requested = false
    private var monitor: NWPathMonitor?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(repository: LocalFinanceRepository, transport: any SyncTransport) {
        self.repository = repository; self.transport = transport
        repository.onMutation = { [weak self] in self?.requestSync() }
    }
    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.requestSync() }
        }
        monitor.start(queue: DispatchQueue(label: "FinanceTracker.connectivity"))
        foreground()
    }
    func foreground() {
        foregroundTimer?.cancel()
        foregroundTimer = Task { [weak self] in
            while !Task.isCancelled {
                self?.materializeDueTransactions()
                self?.requestSync()
                await DailyRateService.shared.refreshIfNeeded()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }
    func background() {
        foregroundTimer?.cancel(); foregroundTimer = nil
        scheduleBackgroundRefresh()
        if worker != nil { beginLimitedBackgroundTime() }
    }
    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundIdentifier, using: nil) { task in
            Task { @MainActor in
                self.scheduleBackgroundRefresh()
                self.materializeDueTransactions()
                self.requestSync()
                var expired = false
                task.expirationHandler = { Task { @MainActor in expired = true; self.cancel() } }
                await self.waitUntilIdle()
                task.setTaskCompleted(success: !expired)
            }
        }
    }
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    private func beginLimitedBackgroundTime() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save finance changes") { [weak self] in
            Task { @MainActor in self?.cancel() }
        }
    }
    func cancel() {
        worker?.cancel(); retry?.cancel()
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    func requestSync() {
        requested = true
        guard worker == nil else { return }
        retry?.cancel(); retry = nil
        worker = Task { [weak self] in
            guard let self else { return }
            repeat {
                requested = false
                await synchronizeOnce()
            } while requested && !Task.isCancelled
            worker = nil
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
            scheduleRetry()
        }
    }
    func waitUntilIdle() async { await worker?.value }

    func materializeDueTransactions(now: Date = .now) {
        guard repository.snapshot.imported else { return }
        // Bound each commit, but finish catch-up without waiting for the network.
        do {
            while repository.snapshot.schedules.values.contains(where: { $0.nextOccurrenceAt.map { $0 <= now } == true }) {
                try repository.edit(now: now) { try $0.materialize(limit: 200) }
            }
        } catch { repository.recordLocalFailure(error) }
    }
    private func synchronizeOnce() async {
        if !repository.snapshot.imported {
            isImporting = true; setupError = nil
            defer { isImporting = false }
            do {
                let snapshot = try await transport.syncBootstrap()
                try Task.checkCancellation()
                try repository.importSnapshot(snapshot)
                materializeDueTransactions()
            } catch {
                if !Task.isCancelled { setupError = error.localizedDescription }
                return
            }
        }
        do {
            // Dependencies stay blocked until their exact predecessor is acknowledged.
            for _ in 0..<100 {
                try Task.checkCancellation()
                let pending = repository.snapshot.pending
                let ids = Set(pending.map(\.id))
                guard let item = pending.first(where: { $0.issue == nil && $0.nextAttempt <= .now && ids.isDisjoint(with: $0.dependencies) }) else { break }
                do {
                    try repository.markSent(item)
                    let response = try await transport.syncPush(item.mutation)
                    try Task.checkCancellation()
                    guard response.mutationId == item.id else { throw APIClientError.invalidResponse }
                    try repository.acknowledge(response, for: item)
                } catch {
                    if case APIClientError.requestFailed(let status, _) = error, [400, 401, 403, 409, 410, 413, 422].contains(status) {
                        try repository.reject(item, message: "This change could not be accepted. Review its values or accept the server version.")
                        continue
                    }
                    if !Task.isCancelled { try repository.recordFailure(item) }
                    throw error
                }
            }
            repeat {
                try Task.checkCancellation()
                let cursor = try repository.value(String.self, key: "cursor") ?? "0"
                let generation = try repository.value(Int.self, key: "generation") ?? 1
                let page = try await transport.syncChanges(cursor: cursor, generation: generation)
                try Task.checkCancellation()
                if page.reset == true {
                    let latest = try await transport.syncBootstrap()
                    try repository.receiveWorkspaceReset(latest)
                    break
                }
                try repository.receive(page)
                if page.hasMore != true { break }
            } while true
            materializeDueTransactions()
            try repository.saveValue(0, key: "syncFailures")
            try repository.saveValue(Date.distantPast, key: "syncRetryAt")
        } catch {
            guard !Task.isCancelled else { return }
            let failures = ((try? repository.value(Int.self, key: "syncFailures")) ?? 0) + 1
            try? repository.saveValue(failures, key: "syncFailures")
            try? repository.saveValue(Date.now.addingTimeInterval(min(300, pow(2, Double(min(failures, 9)))) * Double.random(in: 0.8...1.2)), key: "syncRetryAt")
        }
    }
    private func scheduleRetry() {
        guard repository.snapshot.imported else { return }
        let ids = Set(repository.snapshot.pending.map(\.id))
        var dates = repository.snapshot.pending.filter { $0.issue == nil && ids.isDisjoint(with: $0.dependencies) }.map(\.nextAttempt)
        if let date = try? repository.value(Date.self, key: "syncRetryAt"), date > .distantPast { dates.append(date) }
        guard let date = dates.min() else { return }
        retry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(1, date.timeIntervalSinceNow))) } catch { return }
            self?.requestSync()
        }
    }
}
