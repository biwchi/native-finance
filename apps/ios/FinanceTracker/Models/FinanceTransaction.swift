import Foundation

enum TransactionKind: String, Codable {
    case expense
    case income
}

struct FinanceTransaction: Codable, Identifiable, Hashable {
    let id: UUID
    let accountId: UUID
    let kind: TransactionKind
    let amount: String
    let currency: String
    let category: String?
    let note: String?
    let occurredOn: String
    let createdAt: String
    let updatedAt: String
}

