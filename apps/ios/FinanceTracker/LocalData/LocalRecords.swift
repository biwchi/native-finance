import Foundation
import GRDB

struct LocalSnapshot: Sendable {
    var revision = 0
    var accounts: [UUID: Account] = [:]
    var categories: [UUID: TransactionCategory] = [:]
    var debts: [UUID: Debt] = [:]
    var transactions: [UUID: StoredTransaction] = [:]
    var schedules: [UUID: StoredSchedule] = [:]
    var budgets: [String: MonthlyBudget] = [:]
    var exclusions: [UUID: StoredExclusion] = [:]
    var imported = false
    var pending: [PendingMutation] = []
    var rates: ExchangeRateSnapshot?
    var sortedAccounts: [Account] {
        accounts.values.sorted { ($0.sortOrder ?? 1000, $0.name, $0.createdAt) < ($1.sortOrder ?? 1000, $1.name, $1.createdAt) }
    }
    var detailedTransactions: [FinanceTransaction] {
        transactions.values.map { $0.presentation(in: self) }.sorted {
            $0.occurredAt == $1.occurredAt ? ($0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt) : $0.occurredAt > $1.occurredAt
        }
    }
    func upcoming(now: Date) -> [UpcomingTransaction] {
        schedules.values.compactMap { schedule in
            let recorded = transactions.values.filter { $0.recurringScheduleId == schedule.id && $0.occurredAt > now }.map(\.occurredAt)
            guard let next = ([schedule.nextOccurrenceAt].compactMap { $0 } + recorded).filter({ $0 > now }).filter({ date in schedule.endAt.map { date <= $0 } ?? true }).min() else { return nil }
            return schedule.upcoming(at: next, in: self)
        }.sorted { $0.occurredAt < $1.occurredAt }
    }
    static func load(_ db: Database) throws -> LocalSnapshot {
        var result = LocalSnapshot()
        result.revision = try metadata(Int.self, "revision", db: db) ?? 0
        result.imported = try metadata(Bool.self, "imported", db: db) ?? false
        result.rates = try metadata(ExchangeRateSnapshot.self, "rates", db: db)
        result.pending = try readOutbox(db)
        for row in try Row.fetchAll(db, sql: "SELECT entity,key,data FROM records WHERE data IS NOT NULL") {
            let data: Data = row["data"]
            let entity: String = row["entity"]
            switch entity {
            case "account": let v = try LocalJSON.decoder.decode(Account.self, from: data); result.accounts[v.id] = v
            case "category": let v = try LocalJSON.decoder.decode(TransactionCategory.self, from: data); result.categories[v.id] = v
            case "debt": let v = try LocalJSON.decoder.decode(Debt.self, from: data); result.debts[v.id] = v
            case "transaction": let v = try LocalJSON.decoder.decode(StoredTransaction.self, from: data); result.transactions[v.id] = v
            case "schedule": let v = try LocalJSON.decoder.decode(StoredSchedule.self, from: data); result.schedules[v.id] = v
            case "exclusion": let v = try LocalJSON.decoder.decode(StoredExclusion.self, from: data); result.exclusions[v.id] = v
            case "budget": result.budgets[row["key"]] = try LocalJSON.decoder.decode(MonthlyBudget.self, from: data)
            default: throw LocalDataError(message: "This data requires a newer app version.")
            }
        }
        return result
    }
}
func budgetKey(accountID: UUID?) -> String { accountID?.uuidString.lowercased() ?? "all" }
func bumpLocalRevision(_ db: Database) throws { try setMetadata((try metadata(Int.self, "revision", db: db) ?? 0) + 1, "revision", db: db) }
