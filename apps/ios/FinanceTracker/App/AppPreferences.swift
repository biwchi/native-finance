import SwiftUI

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

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .light: "sun-light"
        case .dark: "half-moon"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}
