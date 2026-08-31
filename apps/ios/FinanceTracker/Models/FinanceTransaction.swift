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
    let description: String?
    let note: String?
    let occurredAt: Date
}
