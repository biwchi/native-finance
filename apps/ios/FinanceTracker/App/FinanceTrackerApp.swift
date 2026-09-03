import SwiftUI

@main
struct FinanceTrackerApp: App {
    @StateObject private var accountStore = AccountStore()
    @StateObject private var budgetStore = BudgetStore()
    @StateObject private var exchangeRateStore = ExchangeRateStore()
    @StateObject private var transactionStore = TransactionStore()
    @AppStorage(AppPreferences.themeKey) private var theme = AppTheme.dark.rawValue

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .tint(AppColor.accent)
                .environmentObject(accountStore)
                .environmentObject(budgetStore)
                .environmentObject(exchangeRateStore)
                .environmentObject(transactionStore)
                .preferredColorScheme(
                    AppTheme(rawValue: theme)?.colorScheme ?? .dark
                )
        }
    }
}
