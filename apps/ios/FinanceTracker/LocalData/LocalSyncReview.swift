import Foundation
import GRDB

extension LocalFinanceRepository {
    var needsSyncReviewRefresh: Bool {
        get throws {
            try requireDatabase().read { db in
                guard try metadata(Bool.self, "pendingReset", db: db) != true,
                      try metadata(SyncSnapshot.self, "remoteReset", db: db) == nil,
                      try readOutbox(db).contains(where: { $0.issue != nil }) else { return false }
                return try metadata(String.self, "reviewCheckedState", db: db) != syncReviewState(db)
            }
        }
    }

    /// Only a complete, current snapshot can prove that a never-synced entry is absent.
    /// Never infer deletion from a missing cached server copy or an upload failure.
    @discardableResult
    func reconcileCompletedChanges(with remote: SyncSnapshot) throws -> Bool {
        let removed = try requireDatabase().write { db in
            guard remote.reset != true, remote.hasMore != true,
                  try metadata(UUID.self, "workspaceID", db: db) == remote.workspaceId,
                  try metadata(Int.self, "generation", db: db) == remote.generation,
                  try metadata(Bool.self, "pendingReset", db: db) != true,
                  try metadata(SyncSnapshot.self, "remoteReset", db: db) == nil else { return false }
            let cursor = try metadata(String.self, "cursor", db: db) ?? "0"
            guard let incoming = UInt64(remote.cursor), let current = UInt64(cursor), incoming >= current else { return false }
            var queue = try readOutbox(db)
            let pendingKeys = Set(queue.flatMap { $0.mutation.changes.map(\.identity) })
            let records = Dictionary(remote.records.map { ($0.identity, $0) }, uniquingKeysWith: { _, newer in newer })
            for record in remote.records { try accept(record, pendingKeys: pendingKeys, db: db) }
            for change in latestSyncChanges(queue) where records[change.identity] == nil {
                try db.execute(sql: "UPDATE records SET serverData=NULL,version=NULL WHERE entity=? AND key=?", arguments: [change.entity, change.key])
            }
            var removedIDs = Set<UUID>()
            for group in syncReviewGroups(queue) {
                let ids = Set(group.map(\.id))
                let externalIDs = Set(queue.map(\.id)).subtracting(ids).subtracting(removedIDs)
                // An uncertain/in-flight upload must replay its receipt, not be replaced.
                guard group.allSatisfy({ $0.mutation.generation == remote.generation && !$0.mutation.reset
                    && (!$0.sent || $0.issue != nil) && externalIDs.isDisjoint(with: $0.dependencies) }) else { continue }
                let changes = latestSyncChanges(group)
                let deletions = Set(changes.filter { $0.data == nil }.map(\.identity))
                let removedSchedules = Set(changes.filter { $0.entity == "schedule" && $0.data == nil
                    && records[$0.identity]?.data == nil }.map(\.key))
                // Recurrence actions can affect rows outside their payload. They are only
                // redundant here when their schedule is confirmed gone.
                guard group.flatMap({ $0.mutation.recurrenceActions ?? [] }).allSatisfy({ removedSchedules.contains($0.scheduleId.uuidString.lowercased()) }) else { continue }
                var orphanExclusions: [SyncChange] = []
                var completed = !changes.isEmpty
                for change in changes {
                    let local = try reviewData(change.entity, change.key, column: "data", db: db)
                    if change.entity == "exclusion", let scheduleID = change.data?["scheduleId"]?.string?.lowercased(),
                       removedSchedules.contains(scheduleID), records[change.identity]?.data == nil,
                       local == change.data {
                        orphanExclusions.append(change)
                        continue
                    }
                    // Require explicit deletion intent, not just an empty local row.
                    if !deletions.contains(change.identity) || local != nil || records[change.identity]?.data != nil {
                        completed = false; break
                    }
                }
                guard completed else { continue }
                for change in orphanExclusions { try storeLocalRecord(entity: change.entity, key: change.key, data: nil, db: db) }
                for id in ids { try db.execute(sql: "DELETE FROM outbox WHERE id=?", arguments: [id.uuidString]) }
                removedIDs.formUnion(ids)
            }
            queue.removeAll { removedIDs.contains($0.id) }
            for var item in queue where !item.sent && !removedIDs.isDisjoint(with: item.dependencies) {
                item.dependencies.removeAll { removedIDs.contains($0) }
                try storeOutbox(item, db: db)
            }
            try setMetadata(remote.cursor, "cursor", db: db)
            try setMetadata(syncReviewState(db), "reviewCheckedState", db: db)
            _ = try LocalSnapshot.load(db)
            try bumpLocalRevision(db)
            return !removedIDs.isEmpty
        }
        try reload()
        return removed
    }

    func syncReviewItems() throws -> [SyncReviewItem] {
        try requireDatabase().read { db in
            let queue = try readOutbox(db)
            let checked = try metadata(String.self, "reviewCheckedState", db: db) == syncReviewState(db)
            return try syncReviewGroups(queue).map { group in
                let rows = try reviewRows(group, checked: checked, db: db)
                var missingReference = false
                for row in rows {
                    for (field, entity) in [("accountId", "account"), ("categoryId", "category"), ("debtId", "debt"), ("recurringScheduleId", "schedule"), ("scheduleId", "schedule")] {
                        guard let key = row.savedData?[field]?.string?.lowercased() else { continue }
                        let local = try reviewData(entity, key, column: "data", db: db)
                        let synced = try reviewData(entity, key, column: "serverData", db: db)
                        let version = try String.fetchOne(db, sql: "SELECT version FROM records WHERE entity=? AND key=?", arguments: [entity, key])
                        if local == nil && synced == nil && (version != nil || checked) { missingReference = true }
                    }
                }
                let visible = rows.filter { $0.savedData != $0.synced || ($0.syncedVersion == nil && !$0.checkedAbsence) }
                return SyncReviewItem(id: group[0].id, rows: visible, hasMissingReference: missingReference,
                    hasKnownDifference: rows.contains { $0.syncedVersion != nil && $0.local != $0.synced }, operationCount: group.count)
            }
        }
    }

    func exportSyncReview(_ id: UUID) throws -> Data {
        try requireDatabase().read { db in
            guard let group = syncReviewGroups(try readOutbox(db)).first(where: { $0[0].id == id }) else {
                throw LocalDataError(message: "These changes have already been resolved.")
            }
            let checked = try metadata(String.self, "reviewCheckedState", db: db) == syncReviewState(db)
            let rows = try reviewRows(group, checked: checked, db: db)
            let export: [String: JSONValue] = [
                "savedEntries": .array(try rows.map { .object(try LocalJSON.object($0)) }),
                "originalChanges": .array(try group.map { .object(try LocalJSON.object($0.mutation)) })
            ]
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(export)
        }
    }

    private func reviewRows(_ group: [PendingMutation], checked: Bool, db: Database) throws -> [SyncReviewRow] {
        try latestSyncChanges(group).map { change in
            let row = try Row.fetchOne(db, sql: "SELECT data,serverData,version FROM records WHERE entity=? AND key=?", arguments: [change.entity, change.key])
            let localBytes: Data? = row?["data"]; let syncedBytes: Data? = row?["serverData"]
            return SyncReviewRow(entity: change.entity, key: change.key,
                local: try localBytes.map { try LocalJSON.decoder.decode([String: JSONValue].self, from: $0) },
                synced: try syncedBytes.map { try LocalJSON.decoder.decode([String: JSONValue].self, from: $0) },
                syncedVersion: row?["version"], checkedAbsence: checked,
                submitted: group.reversed().flatMap { $0.mutation.changes }.first { $0.identity == change.identity && $0.data != nil }?.data,
                queuedDeletion: change.data == nil)
        }
    }

    private func reviewData(_ entity: String, _ key: String, column: String, db: Database) throws -> [String: JSONValue]? {
        let bytes = try Data.fetchOne(db, sql: "SELECT \(column) FROM records WHERE entity=? AND key=?", arguments: [entity, key])
        return try bytes.map { try LocalJSON.decoder.decode([String: JSONValue].self, from: $0) }
    }

    private func syncReviewState(_ db: Database) throws -> String {
        let cursor = try metadata(String.self, "cursor", db: db) ?? "0"
        let generation = try metadata(Int.self, "generation", db: db) ?? 1
        let queue = try readOutbox(db)
        return "\(generation):\(cursor):" + queue.map { "\($0.id):\($0.issue != nil)" }.joined(separator: ",")
    }
}
