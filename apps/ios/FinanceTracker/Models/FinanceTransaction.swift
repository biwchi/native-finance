import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: Self { self }

    var title: String {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        }
    }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}

struct TransactionRecurrence: Codable, Hashable {
    let id: UUID
    let frequency: RecurrenceFrequency
    let endAt: Date?
}

struct RecurrenceRequest: Encodable, Equatable {
    let frequency: RecurrenceFrequency
    let endAt: Date?
}

protocol EditableTransaction {
    var accountId: UUID { get }
    var kind: TransactionKind { get }
    var amount: String { get }
    var currency: String { get }
    var category: TransactionCategory? { get }
    var merchant: String? { get }
    var payee: String? { get }
    var note: String? { get }
    var occurredAt: Date { get }
    var recurrence: TransactionRecurrence? { get }
}

extension EditableTransaction {
    func formattedAmount(showExpenseSign: Bool = true) -> String {
        guard let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else {
            return "Unavailable"
        }
        return MoneyFormatter.format(
            kind == .expense && showExpenseSign ? -value : value,
            currency: currency,
            showPositiveSign: kind == .income
        )
    }
}

struct FinanceTransaction: Codable, Identifiable, Hashable, EditableTransaction {
    let id: UUID
    let accountId: UUID
    let kind: TransactionKind
    let amount: String
    let currency: String
    let category: TransactionCategory?
    var merchant: String? = nil
    var payee: String? = nil
    let note: String?
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date
    var recurrence: TransactionRecurrence? = nil
}

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

struct TransactionRequest: Encodable {
    let accountId: UUID
    let kind: TransactionKind
    let amount: String
    let categoryId: UUID?
    var merchant: String? = nil
    var payee: String? = nil
    let note: String?
    let occurredAt: Date
    var recurrence: RecurrenceRequest? = nil
}

struct RecurringTransactionUpdateRequest: Encodable {
    let transaction: TransactionRequest
    let expectedOccurredAt: Date
}

struct RecurringTransactionUpdateResponse: Decodable {
    let updated: Bool
}

enum RecurringDeletionAction: String, CaseIterable {
    case occurrence
    case stopRepeating
    case occurrenceAndFuture

    var title: String {
        switch self {
        case .occurrence: "Delete only this transaction"
        case .stopRepeating: "Stop repeating"
        case .occurrenceAndFuture: "Delete this and all future"
        }
    }
}

struct TransferRequest: Encodable {
    let fromAccountId: UUID
    let toAccountId: UUID
    let amount: String
    let merchant: String?
    let payee: String?
    let note: String?
    let occurredAt: Date
}

struct TransferResponse: Decodable {
    let source: FinanceTransaction
    let destination: FinanceTransaction
}

struct DeleteTransactionResponse: Decodable {
    let deleted: Bool
}
