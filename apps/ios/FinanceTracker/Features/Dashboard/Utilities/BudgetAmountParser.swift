import Foundation

enum BudgetAmountParser {
    static func parse(_ value: String) -> Decimal? {
        guard let amount = MoneyFormatter.parseInput(value), amount > 0 else {
            return nil
        }
        return amount
    }

    static func normalized(_ value: String) -> String? {
        parse(value).map { NSDecimalNumber(decimal: $0).stringValue }
    }

    static func editable(_ value: String?) -> String {
        guard let value,
              let amount = MoneyFormatter.parseInput(value) else {
            return value ?? ""
        }
        return MoneyFormatter.editingText(amount)
    }
}
