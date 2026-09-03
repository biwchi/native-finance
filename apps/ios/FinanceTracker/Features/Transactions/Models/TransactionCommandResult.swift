import Foundation

struct TransactionCommandResult: Equatable {
    let amount: Decimal?
    let kind: TransactionKind
    let description: String
    let occurredAt: Date?
    let amountConflict: Bool
    let dateConflict: Bool
}
