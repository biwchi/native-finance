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

struct FinanceTransaction: Codable, Identifiable, Hashable {
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
