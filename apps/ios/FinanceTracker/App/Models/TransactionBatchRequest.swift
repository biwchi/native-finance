import Foundation

struct TransactionBatchRequest: Encodable {
    let transactions: [TransactionBatchItem]
}
