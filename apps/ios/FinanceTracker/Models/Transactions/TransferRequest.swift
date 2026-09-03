import Foundation

struct TransferRequest: Encodable {
    let fromAccountId: UUID
    let toAccountId: UUID
    let amount: String
    let merchant: String?
    let payee: String?
    let note: String?
    let occurredAt: Date
}
