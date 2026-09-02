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

enum AccountIconColor: String, Codable, CaseIterable, Identifiable {
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case green
    case teal
    case gray

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}

enum AccountIcon {
    static let choices = [
        "credit-card",
        "bank",
        "cash",
        "dollar-circle",
        "graph-up",
        "home-simple",
        "car",
        "cart",
        "suitcase",
        "gift",
        "airplane",
        "heart",
    ]
}

struct Account: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: AccountType
    let currency: String
    let icon: String
    let iconColor: AccountIconColor
    let createdAt: String
    let updatedAt: String
}

struct AccountRequest: Encodable {
    let name: String
    let type: AccountType
    let currency: String
    let icon: String
    let iconColor: AccountIconColor
}

struct AccountOrderRequest: Encodable {
    let accountIds: [UUID]
}

struct DeleteAccountResponse: Decodable {
    let deleted: Bool
}
