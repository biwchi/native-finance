import Foundation

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
