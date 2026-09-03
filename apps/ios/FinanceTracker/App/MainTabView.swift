import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @EnvironmentObject private var exchangeRateStore: ExchangeRateStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage(AppPreferences.preferSimpleTransactionEntryKey)
    private var preferSimpleTransactionEntry = false
    @AppStorage("lastTransactionAccountID") private var lastTransactionAccountID = ""

    @State private var addPresentation: AddTransactionPresentation?
    @State private var isPresentingQuickEntry = false
    @State private var quickEntryText = ""
    @State private var quickEntryAccountID: UUID?
    @FocusState private var isQuickEntryFocused: Bool

    var body: some View {
        ZStack {
            MainTabController(
                accountStore: accountStore,
                budgetStore: budgetStore,
                exchangeRateStore: exchangeRateStore,
                transactionStore: transactionStore
            ) {
                presentAddTransaction()
            }
            .ignoresSafeArea()

            if isPresentingQuickEntry {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture(perform: handleQuickEntryBackgroundTap)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Spacer()
                    quickEntryComposer
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: isPresentingQuickEntry)
        .onChange(of: isQuickEntryFocused) { _, isFocused in
            if !isFocused, isPresentingQuickEntry {
                dismissQuickEntry()
            }
        }
        .onChange(of: accountStore.accounts) { _, _ in
            if isPresentingQuickEntry {
                configureQuickEntryAccount()
            }
        }
        .sheet(item: $addPresentation) { presentation in
            AddTransactionView(
                initialCommand: presentation.command,
                initialAccountID: presentation.accountID
            )
                .environmentObject(accountStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $accountStore.isManagingAccounts) {
            AccountManagementView()
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
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

    private var quickEntryComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickAccountMenu(
                accounts: accountStore.accounts,
                selectedAccountID: quickEntryAccountID
            ) { accountID in
                quickEntryAccountID = accountID
            }

            HStack(alignment: .top, spacing: 8) {
                TextField(
                    "Coffee 4.50 this morning",
                    text: $quickEntryText,
                    axis: .vertical
                )
                .lineLimit(2...7)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .focused($isQuickEntryFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    Color(uiColor: .tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )

                if !trimmedQuickEntryText.isEmpty {
                    PrimaryIconButton(
                        "Review transaction",
                        iconName: "arrow-up",
                        action: submitQuickEntry
                    )
                    .disabled(quickEntryAccountID == nil)
                    .transition(
                        .scale(scale: 0.72, anchor: .trailing)
                            .combined(with: .opacity)
                    )
                }
            }
            .animation(.snappy(duration: 0.22), value: trimmedQuickEntryText.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityAction(.escape) {
            dismissQuickEntry()
        }
        .task {
            await Task.yield()
            guard isPresentingQuickEntry else { return }
            isQuickEntryFocused = true
        }
    }

    private func presentAddTransaction() {
        if preferSimpleTransactionEntry {
            configureQuickEntryAccount()
            withAnimation(.snappy(duration: 0.25)) {
                isPresentingQuickEntry = true
            }
        } else {
            addPresentation = AddTransactionPresentation(command: nil, accountID: nil)
        }
    }

    private func handleQuickEntryBackgroundTap() {
        dismissQuickEntry()
    }

    private func submitQuickEntry() {
        guard !trimmedQuickEntryText.isEmpty, let quickEntryAccountID else { return }

        let command = trimmedQuickEntryText
        quickEntryText = ""
        dismissQuickEntry()
        addPresentation = AddTransactionPresentation(
            command: command,
            accountID: quickEntryAccountID
        )
    }

    private var trimmedQuickEntryText: String {
        quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dismissQuickEntry() {
        isQuickEntryFocused = false
        withAnimation(.snappy(duration: 0.25)) {
            isPresentingQuickEntry = false
        }
    }

    private func configureQuickEntryAccount() {
        if let quickEntryAccountID,
           accountStore.accounts.contains(where: { $0.id == quickEntryAccountID }) {
            return
        }

        if let selectedAccountID = accountStore.selectedAccountID,
           accountStore.accounts.contains(where: { $0.id == selectedAccountID }) {
            quickEntryAccountID = selectedAccountID
            return
        }

        if let lastAccountID = UUID(uuidString: lastTransactionAccountID),
           accountStore.accounts.contains(where: { $0.id == lastAccountID }) {
            quickEntryAccountID = lastAccountID
            return
        }

        quickEntryAccountID = accountStore.accounts.first?.id
    }
}

private struct AddTransactionPresentation: Identifiable {
    let id = UUID()
    let command: String?
    let accountID: UUID?
}

private struct MainTabController: UIViewControllerRepresentable {
    let accountStore: AccountStore
    let budgetStore: BudgetStore
    let exchangeRateStore: ExchangeRateStore
    let transactionStore: TransactionStore
    var onAdd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAdd: onAdd)
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()
        controller.delegate = context.coordinator
        controller.view.tintColor = UIColor(named: "AccentColor")

        // Keep the same hosting controllers (and navigation/scroll state) when the sheet opens.
        let home = hostingController(DashboardView(), title: "Home", iconName: "home-simple")
        let assistant = hostingController(AssistantView(), title: "Assistant", iconName: "sparks")
        let settingsView = SettingsView { [weak controller] isVisible in
            if #available(iOS 18.0, *) {
                controller?.setTabBarHidden(isVisible, animated: true)
            } else {
                controller?.tabBar.isHidden = isVisible
            }
        }
        let settings = hostingController(settingsView, title: "Settings", iconName: "settings")
        let add = context.coordinator.addViewController
        add.tabBarItem = UITabBarItem(title: "Add", image: AppIcons.uiImage(named: "plus"), tag: 0)

        if #available(iOS 18.0, *) {
            let addTab = UISearchTab { _ in add }
            addTab.title = "Add"
            addTab.image = AppIcons.uiImage(named: "plus")
            controller.tabs = [
                UITab(title: "Home", image: home.tabBarItem.image, identifier: "home") { _ in home },
                UITab(title: "Settings", image: settings.tabBarItem.image, identifier: "settings") { _ in settings },
                addTab
            ]
        } else {
            controller.viewControllers = [home, assistant, settings, add]
        }
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.onAdd = onAdd
    }

    private func hostingController<Content: View>(
        _ content: Content, title: String, iconName: String
    ) -> UIViewController {
        let controller = UIHostingController(
            rootView: content
                .tint(Color("AccentColor"))
                .environmentObject(accountStore)
                .environmentObject(budgetStore)
                .environmentObject(exchangeRateStore)
                .environmentObject(transactionStore)
        )
        controller.tabBarItem = UITabBarItem(title: title, image: AppIcons.uiImage(named: iconName), tag: 0)
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
        .environmentObject(ExchangeRateStore())
        .environmentObject(TransactionStore())
}
