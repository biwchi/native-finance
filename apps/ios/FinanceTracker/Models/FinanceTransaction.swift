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

struct FinanceTransaction: Codable, Identifiable, Hashable {
    let id: UUID
    let accountId: UUID
    let kind: TransactionKind
    let amount: String
    let currency: String
    let category: TransactionCategory?
    var merchant: String? = nil
    var payee: String? = nil
    let description: String?
    let note: String?
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date
}

struct TransactionRequest: Encodable {
    let accountId: UUID
    let kind: TransactionKind
    let amount: String
    let categoryId: UUID?
    var merchant: String? = nil
    var payee: String? = nil
    let description: String?
    let note: String?
    let occurredAt: Date
}

struct TransferRequest: Encodable {
    let fromAccountId: UUID
    let toAccountId: UUID
    let amount: String
    let merchant: String?
    let payee: String?
    let description: String?
    let note: String?
    let occurredAt: Date
}

struct TransferResponse: Decodable {
    let source: FinanceTransaction
    let destination: FinanceTransaction
}
