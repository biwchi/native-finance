import Foundation
import Combine
import GRDB

@MainActor
final class LocalFinanceRepository: ObservableObject {
    static let shared: LocalFinanceRepository = {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("FinanceTracker", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            return try LocalFinanceRepository(path: folder.appendingPathComponent("finance.sqlite").path)
        } catch { return LocalFinanceRepository(error: error) }
    }()
    @Published private(set) var snapshot = LocalSnapshot()
    @Published private(set) var storageError: String?
    var onMutation: (() -> Void)?
    private(set) var database: LocalDatabase?
    private var observation: AnyDatabaseCancellable?
    init(path: String) throws {
        let database = try LocalDatabase(path: path)
        self.database = database
        snapshot = try database.read(LocalSnapshot.load)
        observation = ValueObservation.tracking { try LocalSnapshot.load($0) }.start(in: database.pool, onError: { [weak self] error in
            self?.storageError = error.localizedDescription
        }, onChange: { [weak self] snapshot in
            guard let self, snapshot.revision >= self.snapshot.revision else { return }
            self.snapshot = snapshot
        })
    }
    private init(error: Error) { storageError = error.localizedDescription }
    func requireDatabase() throws -> LocalDatabase {
        guard let database else { throw LocalDataError(message: storageError ?? "Local storage is unavailable") }
        return database
    }
    func reload() throws { snapshot = try requireDatabase().read(LocalSnapshot.load) }
    func value<T: Decodable>(_ type: T.Type, key: String) throws -> T? { try requireDatabase().read { try metadata(type, key, db: $0) } }
    func saveValue<T: Encodable>(_ value: T, key: String) throws { try requireDatabase().write { try setMetadata(value, key, db: $0); try bumpLocalRevision($0) }; try reload() }

    @discardableResult
    func edit<T>(now: Date = .now, _ body: (inout LocalEditor) throws -> T) throws -> T {
        guard snapshot.imported else { throw LocalDataError(message: "Finish the initial import before adding data.") }
        var editor = LocalEditor(snapshot: snapshot, now: now)
        let result = try body(&editor)
        guard !editor.changes.isEmpty || !editor.metadataChanges.isEmpty else { return result }
        try enqueue(Array(editor.changes.values), now: now, metadataChanges: editor.metadataChanges, recurrenceActions: editor.recurrenceActions)
        return result
    }
    private func enqueue(_ changes: [SyncChange], now: Date, reset: Bool = false, metadataChanges: [String: JSONValue] = [:], recurrenceActions: [SyncRecurrenceAction] = []) throws {
        try requireDatabase().write { db in
            var changes = changes.sorted { $0.identity < $1.identity }
            let previous = try readOutbox(db)
            var dependencies = Set<UUID>()
            var keys = Set(changes.map(\.identity))
            for change in changes {
                for (field, entity) in [("accountId","account"),("categoryId","category"),("parentId","category"),("debtId","debt"),("recurringScheduleId","schedule"),("scheduleId","schedule")] {
                    if let id = change.data?[field]?.string { keys.insert("\(entity):\(id.lowercased())") }
                }
                if case .array(let assignments) = change.data?["categoryAssignments"] {
                    for case .object(let assignment) in assignments { if let id = assignment["categoryId"]?.string { keys.insert("category:\(id.lowercased())") } }
                }
            }
            for pending in previous where pending.mutation.reset || !keys.isDisjoint(with: pending.mutation.changes.map(\.identity)) { dependencies.insert(pending.id) }
            for index in changes.indices {
                changes[index].baseVersion = try String.fetchOne(db, sql: "SELECT version FROM records WHERE entity=? AND key=?", arguments: [changes[index].entity,changes[index].key])
                try storeLocalRecord(entity: changes[index].entity, key: changes[index].key, data: changes[index].data, db: db)
            }
            let mutation = SyncMutation(clientId: try metadata(UUID.self, "clientID", db: db)!, mutationId: UUID(), generation: try metadata(Int.self, "generation", db: db) ?? 1, authoredAt: now, changes: changes, reset: reset, workspaceId: try metadata(UUID.self, "workspaceID", db: db), recurrenceActions: recurrenceActions.isEmpty ? nil : recurrenceActions)
            try storeOutbox(PendingMutation(mutation: mutation, dependencies: Array(dependencies), attempts: 0, nextAttempt: .distantPast, sent: false, issue: nil), db: db)
            for (key, value) in metadataChanges { try setMetadata(value, key, db: db) }
            try bumpLocalRevision(db)
        }
        try reload(); onMutation?()
    }
    func importSnapshot(_ imported: SyncSnapshot) throws {
        try requireDatabase().write { db in
            guard try metadata(Bool.self, "imported", db: db) != true else { return }
            try db.execute(sql: "DELETE FROM records")
            for record in imported.records { try accept(record, pendingKeys: [], db: db) }
            try setMetadata(imported.workspaceId, "workspaceID", db: db)
            try setMetadata(imported.generation, "generation", db: db)
            try setMetadata(imported.cursor, "cursor", db: db)
            _ = try LocalSnapshot.load(db) // Validate every row before the import can become visible.
            try setMetadata(true, "imported", db: db)
            try bumpLocalRevision(db)
        }
        try reload()
    }
    func markSent(_ pending: PendingMutation) throws {
        var pending = pending; pending.sent = true
        try requireDatabase().write { try storeOutbox(pending, db: $0); try bumpLocalRevision($0) }; try reload()
    }
    func acknowledge(_ response: SyncResult, for sent: PendingMutation) throws {
        try requireDatabase().write { db in
            var queue = try readOutbox(db)
            guard let index = queue.firstIndex(where: { $0.id == sent.id }) else { return } // A local reset invalidated this request.
            if response.status != "accepted" {
                queue[index].issue = response.message ?? "Review this change before it can be sent."
                try storeOutbox(queue[index], db: db)
            } else {
                try db.execute(sql: "DELETE FROM outbox WHERE id=?", arguments: [sent.id.uuidString])
                queue.remove(at: index)
                for index in queue.indices {
                    if queue[index].dependencies.contains(sent.id) && !queue[index].sent {
                        for j in queue[index].mutation.changes.indices {
                            let identity = queue[index].mutation.changes[j].identity
                            if let record = response.records.last(where: { $0.identity == identity }) { queue[index].mutation.changes[j].baseVersion = record.version }
                        }
                        queue[index].dependencies.removeAll { $0 == sent.id }
                    }
                    if sent.mutation.reset { queue[index].mutation.generation = response.generation }
                    try storeOutbox(queue[index], db: db)
                }
                if sent.mutation.reset {
                    try setMetadata(response.generation, "generation", db: db)
                    try setMetadata(false, "pendingReset", db: db)
                }
            }
            let pendingKeys = Set(queue.flatMap { $0.mutation.changes.map(\.identity) })
            if !(sent.mutation.reset && response.status == "accepted") {
                for record in response.records { try accept(record, pendingKeys: pendingKeys, db: db) }
            }
            _ = try LocalSnapshot.load(db)
            try bumpLocalRevision(db)
        }
        try reload()
    }
    func receive(_ page: SyncSnapshot) throws {
        try requireDatabase().write { db in
            guard try metadata(UUID.self, "workspaceID", db: db) == page.workspaceId else { throw LocalDataError(message: "This server belongs to a different workspace.") }
            if try metadata(Bool.self, "pendingReset", db: db) == true { return }
            let queue = try readOutbox(db)
            if page.reset == true {
                // Never upload old-generation edits into a reset workspace.
                for var item in queue { item.issue = "The workspace was reset elsewhere. Review these local changes."; try storeOutbox(item, db: db) }
                if queue.isEmpty {
                    try db.execute(sql: "DELETE FROM records")
                    try setMetadata(false, "imported", db: db)
                }
                try bumpLocalRevision(db)
                return
            }
            for record in page.records { try accept(record, pendingKeys: Set(queue.flatMap { $0.mutation.changes.map(\.identity) }), db: db) }
            _ = try LocalSnapshot.load(db)
            try setMetadata(page.cursor, "cursor", db: db)
            try bumpLocalRevision(db)
        }
        try reload()
    }
    private func accept(_ record: SyncRecord, pendingKeys: Set<String>, db: Database) throws {
        // Older journal pages contain monthly identities retired by migration 0014.
        if record.entity == "budget", record.key.contains(":") { return }
        if let current = try String.fetchOne(db, sql: "SELECT version FROM records WHERE entity=? AND key=?", arguments: [record.entity, record.key]), let currentVersion = UInt64(current), let incomingVersion = UInt64(record.version), incomingVersion < currentVersion { return }
        if !pendingKeys.contains(record.identity) { try storeLocalRecord(entity: record.entity, key: record.key, data: record.data, db: db) }
        // Keep the server copy separately so received changes never overwrite pending edits.
        let bytes = try record.data.map { try LocalJSON.encoder.encode($0) }
        try db.execute(sql: "INSERT INTO records(entity,key,version,serverData) VALUES (?,?,?,?) ON CONFLICT(entity,key) DO UPDATE SET version=excluded.version,serverData=excluded.serverData", arguments: [record.entity, record.key, record.version, bytes])
    }
    func reject(_ pending: PendingMutation, message: String) throws {
        try requireDatabase().write { db in
            guard var item = try readOutbox(db).first(where: { $0.id == pending.id }) else { return }
            item.issue = message; try storeOutbox(item, db: db); try bumpLocalRevision(db)
        }
        try reload()
    }
    func recordFailure(_ pending: PendingMutation, now: Date = .now) throws {
        try requireDatabase().write { db in
            guard var item = try readOutbox(db).first(where: { $0.id == pending.id }) else { return }
            item.attempts += 1
            item.nextAttempt = now.addingTimeInterval(min(300, pow(2, Double(min(item.attempts, 9)))) * Double.random(in: 0.8...1.2))
            try storeOutbox(item, db: db); try bumpLocalRevision(db)
        }
        try reload()
    }
    func deleteAllData() throws {
        try requireDatabase().write { db in
            let existingReset = try readOutbox(db).first { $0.mutation.reset }
            try db.execute(sql: "DELETE FROM records; DELETE FROM outbox")
            try setMetadata((try metadata(Int.self, "localEpoch", db: db) ?? 0) + 1, "localEpoch", db: db)
            try setMetadata(true, "pendingReset", db: db)
            try setMetadata(Optional<Date>.none, "ratesRefreshedAt", db: db)
            try setMetadata(Optional<ExchangeRateSnapshot>.none, "rates", db: db)
            try setMetadata(Optional<QuickEntryReviewPresentation>.none, "quickEntryReview", db: db)
            try setMetadata("", "quickEntryText", db: db)
            let mutation = SyncMutation(clientId: try metadata(UUID.self, "clientID", db: db)!, mutationId: UUID(), generation: try metadata(Int.self, "generation", db: db) ?? 1, authoredAt: .now, changes: [], reset: true, workspaceId: try metadata(UUID.self, "workspaceID", db: db))
            try storeOutbox(existingReset ?? PendingMutation(mutation: mutation, dependencies: [], attempts: 0, nextAttempt: .distantPast, sent: false, issue: nil), db: db)
            try bumpLocalRevision(db)
        }
        try reload(); onMutation?()
    }
    func localVersion(entity: String, key: String) throws -> [String: JSONValue]? {
        try requireDatabase().read { db in
            let bytes = try Data.fetchOne(db, sql: "SELECT data FROM records WHERE entity=? AND key=?", arguments: [entity, key])
            return try bytes.map { try LocalJSON.decoder.decode([String: JSONValue].self, from: $0) }
        }
    }
    func serverVersion(entity: String, key: String) throws -> [String: JSONValue]? {
        try requireDatabase().read { db in
            let bytes = try Data.fetchOne(db, sql: "SELECT serverData FROM records WHERE entity=? AND key=?", arguments: [entity, key])
            return try bytes.map { try LocalJSON.decoder.decode([String: JSONValue].self, from: $0) }
        }
    }
    func recordLocalFailure(_ error: Error) { storageError = error.localizedDescription }
    func saveRates(_ rates: ExchangeRateSnapshot, refreshedAt: Date?) throws {
        try requireDatabase().write { db in
            try setMetadata(rates, "rates", db: db)
            if let refreshedAt { try setMetadata(refreshedAt, "ratesRefreshedAt", db: db) }
            _ = try LocalSnapshot.load(db)
            try bumpLocalRevision(db)
        }
        try reload()
    }
    func receiveWorkspaceReset(_ latest: SyncSnapshot) throws {
        guard try value(Bool.self, key: "pendingReset") != true else { return }
        guard try value(UUID.self, key: "workspaceID") == latest.workspaceId else { throw LocalDataError(message: "This server belongs to a different workspace.") }
        if repositoryHasPendingWork {
            try requireDatabase().write { db in
                try setMetadata(latest, "remoteReset", db: db)
                for var item in try readOutbox(db) {
                    item.issue = "The workspace was reset elsewhere. Keep this device’s data or accept the server data."
                    try storeOutbox(item, db: db)
                }
                try bumpLocalRevision(db)
            }
            try reload()
        } else {
            try requireDatabase().write { db in
                try db.execute(sql: "DELETE FROM records")
                for record in latest.records { try accept(record, pendingKeys: [], db: db) }
                try setMetadata(latest.generation, "generation", db: db)
                try setMetadata(latest.cursor, "cursor", db: db)
                try bumpLocalRevision(db)
            }
            try reload()
        }
    }
    private var repositoryHasPendingWork: Bool { !snapshot.pending.isEmpty }
    func resolveWorkspaceReset(keepLocal: Bool) throws {
        guard let latest = try value(SyncSnapshot.self, key: "remoteReset") else { return }
        try requireDatabase().write { db in
            let oldQueue = try readOutbox(db)
            var visible = try Row.fetchAll(db, sql: "SELECT entity,key,data FROM records WHERE data IS NOT NULL").map { row -> SyncChange in
                let bytes: Data = row["data"]
                return SyncChange(entity: row["entity"], key: row["key"], data: try LocalJSON.decoder.decode([String: JSONValue].self, from: bytes))
            }
            let visibleKeys = Set(visible.map(\.identity))
            for item in oldQueue { for change in item.mutation.changes where change.data == nil && !visibleKeys.contains(change.identity) && !visible.contains(where: { $0.identity == change.identity }) { visible.append(change) } }
            try db.execute(sql: "DELETE FROM records; DELETE FROM outbox")
            for record in latest.records { try accept(record, pendingKeys: [], db: db) }
            try setMetadata(latest.generation, "generation", db: db)
            try setMetadata(latest.cursor, "cursor", db: db)
            if keepLocal {
                let clientID = try metadata(UUID.self, "clientID", db: db)!
                // Restore parents before their dependents, in bounded, ordered commits.
                let order = ["account":0, "category":1, "debt":2, "schedule":3, "transaction":4, "exclusion":5, "budget":6]
                visible.sort { (order[$0.entity] ?? 9, $0.data?["parentId"]?.string == nil ? 0 : 1) < (order[$1.entity] ?? 9, $1.data?["parentId"]?.string == nil ? 0 : 1) }
                var predecessor: UUID?
                for offset in stride(from: 0, to: visible.count, by: 500) {
                    var changes = Array(visible[offset..<min(offset + 500, visible.count)])
                    for i in changes.indices {
                        changes[i].baseVersion = latest.records.first { $0.identity == changes[i].identity }?.version
                        try storeLocalRecord(entity: changes[i].entity, key: changes[i].key, data: changes[i].data, db: db)
                    }
                    let mutation = SyncMutation(clientId: clientID, mutationId: UUID(), generation: latest.generation, authoredAt: .now, changes: changes, workspaceId: latest.workspaceId)
                    try storeOutbox(PendingMutation(mutation: mutation, dependencies: predecessor.map { [$0] } ?? [], attempts: 0, nextAttempt: .distantPast, sent: false, issue: nil), db: db)
                    predecessor = mutation.mutationId
                }
            }
            try setMetadata(Optional<SyncSnapshot>.none, "remoteReset", db: db)
            try bumpLocalRevision(db)
        }
        try reload(); onMutation?()
    }
    func resolve(_ id: UUID, keepLocal: Bool) throws {
        try requireDatabase().write { db in
            var queue = try readOutbox(db)
            guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
            var item = queue[index]
            guard item.mutation.generation == (try metadata(Int.self, "generation", db: db) ?? 1) else { throw LocalDataError(message: "These changes belong to an older workspace. Export or discard them before restoring current data.") }
            if keepLocal {
                // Submit the latest local graph, including fixes made after this operation was paused.
                var replaced: Set<UUID> = [id]
                var added = true
                while added {
                    added = false
                    for child in queue where !replaced.contains(child.id) && !replaced.isDisjoint(with: child.dependencies) { replaced.insert(child.id); added = true }
                }
                let combined = queue.filter { replaced.contains($0.id) }
                var latest: [String: SyncChange] = [:]
                for pending in combined { for change in pending.mutation.changes { latest[change.identity] = change } }
                var changes = latest.values.sorted { $0.identity < $1.identity }
                for i in changes.indices {
                    let row = try Row.fetchOne(db, sql: "SELECT version,data FROM records WHERE entity=? AND key=?", arguments: [changes[i].entity, changes[i].key])
                    changes[i].baseVersion = row?["version"]
                    let bytes: Data? = row?["data"]
                    changes[i].data = try bytes.map { try LocalJSON.decoder.decode([String: JSONValue].self, from: $0) }
                }
                let replacementID = UUID()
                item.mutation.mutationId = replacementID; item.mutation.changes = changes
                let actions = combined.flatMap { $0.mutation.recurrenceActions ?? [] }
                item.mutation.recurrenceActions = actions.isEmpty ? nil : actions
                item.dependencies = Array(Set(combined.flatMap(\.dependencies)).subtracting(replaced))
                item.issue = nil; item.sent = false; item.attempts = 0; item.nextAttempt = .distantPast
                try db.execute(sql: "UPDATE outbox SET id=?,payload=?,dependencies=?,issue=NULL,sent=0,attempts=0,nextAttempt=0 WHERE id=?", arguments: [replacementID.uuidString,try LocalJSON.encoder.encode(item.mutation),try LocalJSON.encoder.encode(item.dependencies),id.uuidString])
                for removedID in replaced where removedID != id { try db.execute(sql: "DELETE FROM outbox WHERE id=?", arguments: [removedID.uuidString]) }
            } else {
                // Discard descendants too; retaining a dependent transfer/create would create an invalid graph.
                var removed: Set<UUID> = [id]
                var changed = true
                while changed { changed = false; for child in queue where !removed.contains(child.id) && !removed.isDisjoint(with: child.dependencies) { removed.insert(child.id); changed = true } }
                let keys = Set(queue.filter { removed.contains($0.id) }.flatMap { $0.mutation.changes.map(\.identity) })
                for removedID in removed { try db.execute(sql: "DELETE FROM outbox WHERE id=?", arguments: [removedID.uuidString]) }
                queue.removeAll { removed.contains($0.id) }
                let pendingKeys = Set(queue.flatMap { $0.mutation.changes.map(\.identity) })
                for row in try Row.fetchAll(db, sql: "SELECT entity,key,serverData FROM records") {
                    let entity: String = row["entity"]; let key: String = row["key"]
                    if keys.contains("\(entity):\(key)"), !pendingKeys.contains("\(entity):\(key)") {
                        let bytes: Data? = row["serverData"]
                        try storeLocalRecord(entity: entity, key: key, data: try bytes.map { try LocalJSON.decoder.decode([String: JSONValue].self, from: $0) }, db: db)
                    }
                }
            }
            try bumpLocalRevision(db)
        }
        try reload(); onMutation?()
    }
}
