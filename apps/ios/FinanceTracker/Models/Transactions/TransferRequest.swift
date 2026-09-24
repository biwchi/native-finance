import Foundation

struct TransferRequest: Encodable {
    let fromAccountId: UUID
    let toAccountId: UUID
    let amount: String
    let note: String?
    let occurredAt: Date
    var counterparty: String? = nil
}
