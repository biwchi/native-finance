import Foundation

struct RecurringTransactionUpdateRequest: Encodable {
    let transaction: TransactionRequest
    let expectedOccurredAt: Date
}
