import SwiftUI

@main
struct FinanceTrackerApp: App {
    @State private var sessionID = UUID()
    @AppStorage(AppPreferences.themeKey) private var theme = AppTheme.dark.rawValue

    var body: some Scene {
        WindowGroup {
            FinanceSessionView()
                .id(sessionID)
                .preferredColorScheme(AppTheme(rawValue: theme)?.colorScheme ?? .dark)
                .onReceive(NotificationCenter.default.publisher(for: AppPreferences.dataDeletedNotification)) { _ in
                    sessionID = UUID()
                }
        }
    }

    // Replacing the session after deletion discards every cache and pending store request.
    private struct FinanceSessionView: View {
        @StateObject private var accountStore = AccountStore()
        @StateObject private var budgetStore = BudgetStore()
        @StateObject private var exchangeRateStore = ExchangeRateStore()
        @StateObject private var transactionStore = TransactionStore()

        var body: some View {
            MainView()
                .tint(AppColor.accent)
                .modifier(PreferenceCalendarModifier())
                .environmentObject(accountStore)
                .environmentObject(budgetStore)
                .environmentObject(exchangeRateStore)
                .environmentObject(transactionStore)
        }
    }
}
