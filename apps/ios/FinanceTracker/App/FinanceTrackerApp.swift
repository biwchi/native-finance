import SwiftUI

@main
struct FinanceTrackerApp: App {
    @StateObject private var accountStore = AccountStore()
    @StateObject private var transactionStore = TransactionStore()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
        }
    }
}
