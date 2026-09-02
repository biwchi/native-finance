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

    var systemImage: String {
        switch self {
        case .cash: "banknote"
        case .checking: "building.columns"
        case .savings: "dollarsign.circle"
        case .credit: "creditcard"
        case .investment: "chart.line.uptrend.xyaxis"
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
        "creditcard.fill",
        "building.columns.fill",
        "banknote.fill",
        "dollarsign.circle.fill",
        "chart.line.uptrend.xyaxis",
        "house.fill",
        "car.fill",
        "cart.fill",
        "briefcase.fill",
        "gift.fill",
        "airplane",
        "heart.fill",
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
