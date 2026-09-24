import Foundation
import GRDB

struct StoredSchedule: Codable, Equatable, Sendable {
    var id: UUID
    var accountId: UUID
    var kind: TransactionKind
    var amount: String
    var currency: String
    var categoryId: UUID?
    var note: String?
    var frequency: RecurrenceFrequency
    var startAt: Date
    var lastOccurrenceAt: Date
    var nextOccurrenceAt: Date?
    var endAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var nextScheduledFor: Date? = nil
    var counterparty: String? = nil
    func upcoming(at date: Date, in snapshot: LocalSnapshot) -> UpcomingTransaction {
        let amount = amount.hasPrefix("-") ? String(amount.dropFirst()) : amount
        return UpcomingTransaction(id: id, accountId: accountId, kind: kind, amount: amount, currency: currency,
            category: categoryId.flatMap { snapshot.categories[$0] }, note: note,
            frequency: frequency, occurredAt: date, endAt: endAt, startAt: startAt, counterparty: counterparty)
    }
    func next(after date: Date) -> Date? {
        let bill = UpcomingTransaction(id: id, accountId: accountId, kind: kind, amount: amount, currency: currency,
            category: nil, note: note, frequency: frequency, occurredAt: date,
            endAt: endAt, startAt: startAt, counterparty: counterparty)
        guard let next = RecurrenceSchedule.nextOccurrence(after: date, bill: bill), endAt.map({ next <= $0 }) ?? true else { return nil }
        return next
    }
}
