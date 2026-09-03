import Foundation

enum TransactionListAlert: Identifiable {
    case confirmDeletion(FinanceTransaction)
    case error(String)

    var id: String {
        switch self {
        case let .confirmDeletion(transaction): "delete-\(transaction.id.uuidString)"
        case let .error(message): "error-\(message)"
        }
    }

    var title: String {
        switch self {
        case let .confirmDeletion(transaction):
            transaction.recurrence == nil ? "Delete transaction?" : "Choose an action"
        case .error: "Couldn't delete transaction"
        }
    }
}
