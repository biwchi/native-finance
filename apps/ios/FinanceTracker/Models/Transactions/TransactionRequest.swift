import Foundation

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
