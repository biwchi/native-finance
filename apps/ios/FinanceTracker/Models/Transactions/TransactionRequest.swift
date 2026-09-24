import Foundation

struct TransactionRequest: Encodable {
    let accountId: UUID
    let kind: TransactionKind
    let amount: String
    let categoryId: UUID?
    let note: String?
    let occurredAt: Date
    var debtId: UUID? = nil
    var recurrence: RecurrenceRequest? = nil
    var currency: String? = nil
    var counterparty: String? = nil
}
