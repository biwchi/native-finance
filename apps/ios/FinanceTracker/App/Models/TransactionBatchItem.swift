import Foundation

enum TransactionBatchItem: Encodable {
    case transaction(TransactionRequest)
    case transfer(TransferRequest)

    private enum CodingKeys: String, CodingKey {
        case type
        case transaction
        case transfer
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .transaction(transaction):
            try container.encode("transaction", forKey: .type)
            try container.encode(transaction, forKey: .transaction)
        case let .transfer(transfer):
            try container.encode("transfer", forKey: .type)
            try container.encode(transfer, forKey: .transfer)
        }
    }
}
