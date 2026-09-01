import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @State private var isPresentingAddSheet = false

    var body: some View {
        MainTabController(
            accountStore: accountStore,
            budgetStore: budgetStore,
            transactionStore: transactionStore
        ) {
            isPresentingAddSheet = true
        }
        .ignoresSafeArea()
        .sheet(isPresented: $isPresentingAddSheet) {
            AddTransactionView()
                .environmentObject(accountStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .quickAddSheetBackground()
        }
        .sheet(item: $accountStore.editor) { editor in
            AccountEditorView(account: editor.account)
                .environmentObject(accountStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Couldn’t load accounts",
            isPresented: Binding(
                get: { accountStore.alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        accountStore.alertMessage = nil
                    }
                }
            ),
            actions: {
                Button("Try Again") {
                    Task {
                        await accountStore.loadAccounts(force: true)
                    }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text(accountStore.alertMessage ?? "Unknown error")
            }
        )
        .task {
            await accountStore.loadAccounts()
        }
        .task(id: accountStore.selectedAccountID) {
            await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        }
    }
}

private extension View {
    @ViewBuilder
    func quickAddSheetBackground() -> some View {
        if #available(iOS 26.0, *) {
            presentationBackground(.ultraThinMaterial)
        } else {
            self
        }
    }
}

private struct MainTabController: UIViewControllerRepresentable {
    let accountStore: AccountStore
    let budgetStore: BudgetStore
    let transactionStore: TransactionStore
    var onAdd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAdd: onAdd)
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()
        controller.delegate = context.coordinator
        controller.view.tintColor = UIColor(Color.accentColor)

        // Keep the same hosting controllers (and navigation/scroll state) when the sheet opens.
        let home = hostingController(DashboardView(), title: "Home", systemImage: "house")
        let transactions = hostingController(
            TransactionsView(), title: "Transactions", systemImage: "list.bullet.rectangle"
        )
        let assistant = hostingController(AssistantView(), title: "Assistant", systemImage: "sparkles")
        let settings = hostingController(SettingsView(), title: "Settings", systemImage: "gearshape")
        let add = context.coordinator.addViewController
        add.tabBarItem = UITabBarItem(title: "Add", image: UIImage(systemName: "plus"), tag: 0)

        if #available(iOS 18.0, *) {
            let addTab = UISearchTab { _ in add }
            addTab.title = "Add"
            addTab.image = UIImage(systemName: "plus")
            controller.tabs = [
                UITab(title: "Home", image: home.tabBarItem.image, identifier: "home") { _ in home },
                UITab(title: "Transactions", image: transactions.tabBarItem.image, identifier: "transactions") { _ in transactions },
                UITab(title: "Settings", image: settings.tabBarItem.image, identifier: "settings") { _ in settings },
                addTab
            ]
        } else {
            controller.viewControllers = [home, transactions, assistant, settings, add]
        }
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.onAdd = onAdd
    }

    private func hostingController<Content: View>(
        _ content: Content, title: String, systemImage: String
    ) -> UIViewController {
        let controller = UIHostingController(
            rootView: content
                .environmentObject(accountStore)
                .environmentObject(budgetStore)
                .environmentObject(transactionStore)
        )
        controller.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: systemImage), tag: 0)
        return controller
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        let addViewController = UIViewController()
        var onAdd: () -> Void

        init(onAdd: @escaping () -> Void) {
            self.onAdd = onAdd
        }

        @available(iOS 18.0, *)
        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            shouldSelect(tab.viewController)
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            shouldSelect(viewController)
        }

        private func shouldSelect(_ viewController: UIViewController?) -> Bool {
            guard viewController === addViewController else { return true }

            // Veto selection before UIKit transitions to the empty Add tab. Rejecting a
            // SwiftUI selection binding happens too late to prevent a visible flash.
            onAdd()
            return false
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AccountStore())
        .environmentObject(BudgetStore())
        .environmentObject(TransactionStore())
}
