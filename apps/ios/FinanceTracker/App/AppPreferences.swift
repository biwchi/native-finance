import Foundation

enum AppPreferences {
    static let dataDeletedNotification = Notification.Name("financeDataDeleted")
    static let defaultCurrencyKey = "defaultCurrency"
    static let favoriteCurrenciesKey = "favoriteCurrencies"
    static let firstWeekdayKey = "firstWeekday"
    static let firstWeekdayOptions = [2, 1, 7]
    static let roundTotalsKey = "roundTotals"
    static let useAllocatedBudgetForSummaryKey = "useAllocatedBudgetForSummary"
    static let defaultUseAllocatedBudgetForSummary = true
    static let themeKey = "theme"
    static let preferSimpleTransactionEntryKey = "preferSimpleTransactionEntry"
    static let openScanDraftsAutomaticallyKey = "openScanDraftsAutomatically"
    static let recurringReminderDaysKey = "recurringReminderDays"
    static let defaultRecurringReminderDays = 3
    static let recurringReminderDaysRange = 1...7

    static func normalizedRecurringReminderDays(_ days: Int) -> Int {
        min(max(days, recurringReminderDaysRange.lowerBound), recurringReminderDaysRange.upperBound)
    }

    static var initialCurrency: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    static let currencyCodes = Locale.Currency.isoCurrencies
        .map(\.identifier)
        .sorted()
}

// Calendar weekday numbers are Sunday = 1 through Saturday = 7.
extension AppPreferences {
    static func normalizedFirstWeekday(_ weekday: Int, base: Calendar = .current) -> Int {
        if firstWeekdayOptions.contains(weekday) { return weekday }
        // Preserve the device's week start for legacy defaults when it is supported.
        return firstWeekdayOptions.contains(base.firstWeekday) ? base.firstWeekday : 2
    }

    static func calendar(firstWeekday: Int, base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = normalizedFirstWeekday(firstWeekday, base: base)
        return calendar
    }
}
