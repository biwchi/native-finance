import Foundation

struct Account: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let currency: String
    let icon: String
    let iconColor: AccountIconColor
    let createdAt: String
    let updatedAt: String
    var sortOrder: Int? = nil
    var initialBalance: String = "0"
}

// Accounts saved before initial balances were introduced start at zero.
extension Account {
    static func initialBalanceValue(_ text: String) throws -> String {
        let normalized = text.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        if normalized.isEmpty { return "0" }
        guard normalized.range(of: #"^-?(?:0|[1-9][0-9]{0,14})(?:\.[0-9]{1,4})?$"#, options: .regularExpression) != nil,
              let value = MoneyFormatter.parseInput(normalized) else {
            throw LocalDataError(message: "Enter an initial balance with at most four decimal places.")
        }
        return NSDecimalNumber(decimal: value).stringValue
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        currency = try values.decode(String.self, forKey: .currency)
        icon = try values.decode(String.self, forKey: .icon)
        iconColor = try values.decode(AccountIconColor.self, forKey: .iconColor)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        updatedAt = try values.decode(String.self, forKey: .updatedAt)
        sortOrder = try values.decodeIfPresent(Int.self, forKey: .sortOrder)
        initialBalance = try values.decodeIfPresent(String.self, forKey: .initialBalance) ?? "0"
    }
}
