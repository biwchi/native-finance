import Foundation
import GRDB

struct StoredTransaction: Codable, Equatable, Sendable {
    var id: UUID
    var accountId: UUID
    var kind: TransactionKind
    var amount: String
    var currency: String
    var categoryId: UUID?
    var debtId: UUID?
    var recurringScheduleId: UUID?
    var scheduledFor: Date?
    var note: String?
    var occurredAt: Date
    var createdAt: Date
    var updatedAt: Date
    var counterparty: String? = nil
    func presentation(in snapshot: LocalSnapshot) -> FinanceTransaction {
        let schedule = recurringScheduleId.flatMap { snapshot.schedules[$0] }
        let amount = amount.hasPrefix("-") ? String(amount.dropFirst()) : amount
        return FinanceTransaction(id: id, accountId: accountId, kind: kind, amount: amount, currency: currency,
            category: categoryId.flatMap { snapshot.categories[$0] }, note: note,
            occurredAt: occurredAt, createdAt: createdAt, updatedAt: updatedAt, debtId: debtId,
            debt: debtId.flatMap { snapshot.debts[$0] }, recurrence: schedule.map { TransactionRecurrence(id: $0.id, frequency: $0.frequency, endAt: $0.endAt) }, counterparty: counterparty)
    }
}
