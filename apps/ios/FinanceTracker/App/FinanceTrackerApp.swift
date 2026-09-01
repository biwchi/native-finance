import SwiftUI

@main
struct FinanceTrackerApp: App {
    @StateObject private var accountStore = AccountStore()
    @StateObject private var transactionStore = TransactionStore()
    @AppStorage(AppPreferences.themeKey) private var theme = AppTheme.dark.rawValue

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
                .preferredColorScheme(
                    AppTheme(rawValue: theme)?.colorScheme ?? .dark
                )
        }
    }
}
