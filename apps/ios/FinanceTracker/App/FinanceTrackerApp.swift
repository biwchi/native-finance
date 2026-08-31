import SwiftUI

@main
struct FinanceTrackerApp: App {
    @StateObject private var accountStore = AccountStore()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(accountStore)
        }
    }
}
