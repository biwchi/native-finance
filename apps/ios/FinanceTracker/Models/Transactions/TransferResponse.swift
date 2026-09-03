import Foundation

struct TransferResponse: Decodable {
    let source: FinanceTransaction
    let destination: FinanceTransaction
}
