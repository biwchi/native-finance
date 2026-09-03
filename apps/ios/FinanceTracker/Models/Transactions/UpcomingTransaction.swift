import Foundation

struct UpcomingTransaction: Codable, Identifiable, Hashable, EditableTransaction {
    let id: UUID
    let accountId: UUID
    let kind: TransactionKind
    let amount: String
    let currency: String
    var category: TransactionCategory?
    let merchant: String?
    let payee: String?
    let note: String?
    let frequency: RecurrenceFrequency
    let occurredAt: Date
    var endAt: Date? = nil
    /// Original schedule anchor, used to preserve month-end and leap-day repeats.
    var startAt: Date? = nil

    var recurrence: TransactionRecurrence? {
        TransactionRecurrence(id: id, frequency: frequency, endAt: endAt)
    }

    var title: String {
        let counterparty = kind == .income ? payee : merchant
        return [counterparty, note, category?.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Recurring \(kind.title.lowercased())"
    }

    var amountText: String {
        formattedAmount(showExpenseSign: false)
    }
}
