import Foundation

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case cash
    case checking
    case savings
    case credit
    case investment

    var id: Self { self }

    var title: String {
        switch self {
        case .cash: "Cash"
        case .checking: "Checking"
        case .savings: "Savings"
        case .credit: "Credit card"
        case .investment: "Investment"
        }
    }

    var iconName: String {
        switch self {
        case .cash: "cash"
        case .checking: "bank"
        case .savings: "dollar-circle"
        case .credit: "credit-card"
        case .investment: "graph-up"
        }
    }
}
