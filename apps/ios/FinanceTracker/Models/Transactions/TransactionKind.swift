import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income
    case debt

    var id: Self { self }

    var title: String {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        case .debt: "Debt"
        }
    }
}
