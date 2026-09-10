import Foundation
import GRDB

/// Domain rows and their durable outbox share the same SQLite commit.
final class LocalDatabase {
    let pool: DatabasePool
    init(path: String) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        pool = try DatabasePool(path: path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("local-first-v1") { db in
            try db.execute(sql: """
                CREATE TABLE records (
                    entity TEXT NOT NULL, key TEXT NOT NULL, data BLOB, serverData BLOB, version TEXT,
                    accountId TEXT, categoryId TEXT, debtId TEXT, scheduleId TEXT, occurredAt TEXT, month TEXT,
                    PRIMARY KEY(entity, key));
                CREATE INDEX records_account_date ON records(entity, accountId, occurredAt);
                CREATE INDEX records_category ON records(categoryId);
                CREATE INDEX records_debt ON records(debtId);
                CREATE INDEX records_schedule ON records(scheduleId);
                CREATE INDEX records_month ON records(entity, accountId, month);
                CREATE TABLE metadata (key TEXT PRIMARY KEY, value BLOB NOT NULL);
                CREATE TABLE outbox (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, payload BLOB NOT NULL,
                    dependencies BLOB NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
                    nextAttempt DOUBLE NOT NULL DEFAULT 0, sent BOOLEAN NOT NULL DEFAULT 0, issue TEXT);
                """)
        }
        migrator.registerMigration("global-budgets-v2") { db in
            try migrateGlobalBudgets(db)
        }
        try migrator.migrate(pool)
        try pool.write { db in
            if try metadata(UUID.self, "clientID", db: db) == nil { try setMetadata(UUID(), "clientID", db: db) }
        }
    }
    func read<T>(_ body: (Database) throws -> T) throws -> T { try pool.read(body) }
    func write<T>(_ body: (Database) throws -> T) throws -> T { try pool.write(body) }
}

func metadata<T: Decodable>(_ type: T.Type, _ key: String, db: Database) throws -> T? {
    guard let bytes = try Data.fetchOne(db, sql: "SELECT value FROM metadata WHERE key = ?", arguments: [key]) else { return nil }
    if bytes == Data("null".utf8) { return nil }
    return try LocalJSON.decoder.decode(type, from: bytes)
}
func setMetadata<T: Encodable>(_ value: T, _ key: String, db: Database) throws {
    try db.execute(sql: "INSERT INTO metadata(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", arguments: [key, try LocalJSON.encoder.encode(value)])
}
func readOutbox(_ db: Database) throws -> [PendingMutation] {
    try Row.fetchAll(db, sql: "SELECT * FROM outbox ORDER BY sequence").map { row in
        PendingMutation(mutation: try LocalJSON.decoder.decode(SyncMutation.self, from: row["payload"]), dependencies: try LocalJSON.decoder.decode([UUID].self, from: row["dependencies"]), attempts: row["attempts"], nextAttempt: Date(timeIntervalSince1970: row["nextAttempt"]), sent: row["sent"], issue: row["issue"])
    }
}
func storeOutbox(_ item: PendingMutation, db: Database) throws {
    try db.execute(sql: """
        INSERT INTO outbox(id,payload,dependencies,attempts,nextAttempt,sent,issue) VALUES (?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET payload=excluded.payload, dependencies=excluded.dependencies,
        attempts=excluded.attempts,nextAttempt=excluded.nextAttempt,sent=excluded.sent,issue=excluded.issue
        """, arguments: [item.id.uuidString, try LocalJSON.encoder.encode(item.mutation), try LocalJSON.encoder.encode(item.dependencies), item.attempts, item.nextAttempt.timeIntervalSince1970, item.sent, item.issue])
}
func storeLocalRecord(entity: String, key: String, data: [String: JSONValue]?, db: Database) throws {
    let bytes = try data.map { try LocalJSON.encoder.encode($0) }
    try db.execute(sql: """
        INSERT INTO records(entity,key,data,accountId,categoryId,debtId,scheduleId,occurredAt,month) VALUES (?,?,?,?,?,?,?,?,?)
        ON CONFLICT(entity,key) DO UPDATE SET data=excluded.data,accountId=excluded.accountId,categoryId=excluded.categoryId,
        debtId=excluded.debtId,scheduleId=excluded.scheduleId,occurredAt=excluded.occurredAt,month=excluded.month
        """, arguments: [entity,key,bytes,data?["accountId"]?.string,data?["categoryId"]?.string,data?["debtId"]?.string,data?["recurringScheduleId"]?.string ?? data?["scheduleId"]?.string,data?["occurredAt"]?.string,data?["month"]?.string])
}

/// Replace month identities once, preserving offline edits and their upload dependencies.
func migrateGlobalBudgets(_ db: Database) throws {
    var budgets: [String: MonthlyBudget] = [:]
    let rows = try Row.fetchAll(db, sql: "SELECT key,data FROM records WHERE entity='budget'")
    for row in rows {
        guard let bytes: Data = row["data"] else { continue }
        let budget = try LocalJSON.decoder.decode(MonthlyBudget.self, from: bytes)
        let key = budgetKey(accountID: budget.accountId)
        if let previous = budgets[key], (previous.updatedAt, previous.id.uuidString) > (budget.updatedAt, budget.id.uuidString) { continue }
        budgets[key] = budget
    }
    let queue = try readOutbox(db)
    var replacements: [UUID: UUID] = [:]
    var precedingBudgetEdits: [String: UUID] = [:]
    for var pending in queue {
        let oldID = pending.id
        var changes: [String: SyncChange] = [:]
        var budgetKeys = Set<String>()
        for change in pending.mutation.changes {
            guard change.entity == "budget" else { changes[change.identity] = change; continue }
            let key = String(change.key.split(separator: ":")[0]).lowercased()
            var data = change.data
            data?.removeValue(forKey: "month")
            let migrated = SyncChange(entity: "budget", key: key, baseVersion: nil, data: data)
            // A single legacy commit can include several months of the same account.
            if let prior = changes[migrated.identity], let priorData = prior.data, let data {
                let oldBudget = try LocalJSON.decode(MonthlyBudget.self, priorData)
                let newBudget = try LocalJSON.decode(MonthlyBudget.self, data)
                if (oldBudget.updatedAt, oldBudget.id.uuidString) > (newBudget.updatedAt, newBudget.id.uuidString) { continue }
            }
            changes[migrated.identity] = migrated
            budgetKeys.insert(key)
        }
        pending.dependencies = pending.dependencies.map { replacements[$0] ?? $0 }
        if !budgetKeys.isEmpty {
            // Sent payloads are immutable on the server. Use a fresh receipt identity.
            pending.mutation.mutationId = UUID()
            replacements[oldID] = pending.id
            pending.mutation.changes = changes.values.sorted { $0.identity < $1.identity }
            pending.sent = false
            pending.attempts = 0
            pending.nextAttempt = .distantPast
            for key in budgetKeys {
                if let previous = precedingBudgetEdits[key] { pending.dependencies.append(previous) }
                precedingBudgetEdits[key] = pending.id
                if let data = changes["budget:\(key)"]?.data {
                    budgets[key] = try LocalJSON.decode(MonthlyBudget.self, data)
                } else {
                    budgets.removeValue(forKey: key)
                }
            }
            pending.dependencies = Array(Set(pending.dependencies))
        }
        // Keep sequence order, including operations with no budget changes.
        try db.execute(sql: "UPDATE outbox SET id=?,payload=?,dependencies=?,attempts=?,nextAttempt=?,sent=? WHERE id=?",
                       arguments: [pending.id.uuidString, try LocalJSON.encoder.encode(pending.mutation), try LocalJSON.encoder.encode(pending.dependencies), pending.attempts, pending.nextAttempt.timeIntervalSince1970, pending.sent, oldID.uuidString])
    }
    try db.execute(sql: "DELETE FROM records WHERE entity='budget'")
    for (key, budget) in budgets {
        try storeLocalRecord(entity: "budget", key: key, data: try LocalJSON.object(budget), db: db)
    }
    // Global server versions arrive through the normal change feed. Pending edits
    // keep a nil base version and use the existing conflict review if necessary.
    try bumpLocalRevision(db)
}
