import SwiftUI

@main
struct FinanceTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var repository = LocalFinanceRepository.shared
    @StateObject private var sync = SyncCoordinator.shared
    init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { SyncCoordinator.shared.registerBackgroundRefresh() }
    }
    @State private var sessionID = UUID()
    @AppStorage(AppPreferences.themeKey) private var theme = AppTheme.dark.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if repository.snapshot.imported { FinanceSessionView().id(sessionID) }
                else { LocalSetupView(repository: repository, sync: sync) }
            }
                .task {
                    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { sync.start() }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    if phase == .active { sync.foreground() }
                    if phase == .background { sync.background() }
                }
                .preferredColorScheme(AppTheme(rawValue: theme)?.colorScheme ?? .dark)
                .onReceive(NotificationCenter.default.publisher(for: AppPreferences.dataDeletedNotification)) { _ in
                    sessionID = UUID()
                }
        }
    }

    // Recreate presentations after a local reset; the durable sync worker survives.
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
