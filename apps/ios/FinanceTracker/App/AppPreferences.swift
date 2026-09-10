import Foundation

enum AppPreferences {
    static let dataDeletedNotification = Notification.Name("financeDataDeleted")
    static let defaultCurrencyKey = "defaultCurrency"
    static let firstWeekdayKey = "firstWeekday"
    static let roundTotalsKey = "roundTotals"
    static let useAllocatedBudgetForSummaryKey = "useAllocatedBudgetForSummary"
    static let defaultUseAllocatedBudgetForSummary = true
    static let themeKey = "theme"
    static let preferSimpleTransactionEntryKey = "preferSimpleTransactionEntry"
    static let recurringReminderDaysKey = "recurringReminderDays"
    static let defaultRecurringReminderDays = 3
    static let recurringReminderDaysRange = 0...30

    static var initialCurrency: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    static let currencyCodes = Locale.Currency.isoCurrencies
        .map(\.identifier)
        .sorted()
}

// Calendar weekday numbers are Sunday = 1 through Saturday = 7; 0 follows the device.
extension AppPreferences {
    static func calendar(firstWeekday: Int, base: Calendar = .current) -> Calendar {
        var calendar = base
        if (1...7).contains(firstWeekday) {
            calendar.firstWeekday = firstWeekday
        }
        return calendar
    }
}
