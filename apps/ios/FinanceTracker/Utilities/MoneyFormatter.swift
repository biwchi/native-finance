import Foundation

/// App-wide money display: a leading symbol, space grouping, and two comma decimals.
enum MoneyFormatter {
    static let decimalSeparator = ","
    private static let displayLocale = Locale(identifier: "fr_FR")
    private static let symbolLocale = Locale(identifier: "en_US")

    static func format(_ value: Decimal, currency: String, showPositiveSign: Bool = false) -> String {
        guard !value.isNaN else { return "Unavailable" }
        let amount = rounded(value)
        let sign = amount < 0 ? "-" : (showPositiveSign && amount > 0 ? "+" : "")
        return sign + symbol(for: currency) + number(abs(amount))
    }

    static func number(_ value: Decimal) -> String {
        guard !value.isNaN else { return "Unavailable" }
        return rounded(value).formatted(
            .number.grouping(.automatic).precision(.fractionLength(2)).locale(displayLocale)
        )
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    static func symbol(for currency: String) -> String {
        let code = currency.uppercased()
        let formatted = Decimal.zero.formatted(
            .currency(code: code).presentation(.narrow).locale(symbolLocale).attributed
        )
        let symbol = formatted.runs.filter { $0.numberSymbol == .currency }
            .map { String(formatted[$0.range].characters) }.joined()
        return symbol.isEmpty ? code : symbol
    }

    /// VoiceOver uses the user's language to pronounce currency names and numbers.
    static func spoken(_ value: Decimal, currency: String, locale: Locale) -> String {
        guard !value.isNaN else { return "Unavailable" }
        return rounded(value).formatted(
            .currency(code: currency.uppercased()).presentation(.fullName)
                .precision(.fractionLength(2)).locale(locale)
        )
    }

    /// Editing keeps every stored decimal; two-place rounding is only for display.
    static func editingText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
            .replacingOccurrences(of: ".", with: decimalSeparator)
    }

    /// Accept app-formatted numbers and decimal keyboard input without locale guessing.
    static func parseInput(_ text: String) -> Decimal? {
        let normalized = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: decimalSeparator, with: ".")
        guard normalized.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else { return nil }
        return value
    }

    private static func rounded(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .plain)
        return result == 0 ? .zero : result
    }
}
