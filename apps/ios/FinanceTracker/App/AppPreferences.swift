import Foundation

enum AppPreferences {
    static let defaultCurrencyKey = "defaultCurrency"
    static let themeKey = "theme"
    static let preferSimpleTransactionEntryKey = "preferSimpleTransactionEntry"

    static var initialCurrency: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    static let currencyCodes = Locale.Currency.isoCurrencies
        .map(\.identifier)
        .sorted()
}
