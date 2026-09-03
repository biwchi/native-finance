import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: Self { self }

    var title: String {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        }
    }
}
