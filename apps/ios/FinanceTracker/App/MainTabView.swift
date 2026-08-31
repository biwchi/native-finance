import SwiftUI

private enum AppTab: Hashable {
    case home
    case transactions
    case assistant
    case add
}

struct MainTabView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @State private var selection: AppTab = .home
    @State private var isPresentingAddSheet = false

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                modernTabView
            } else {
                legacyTabView
            }
        }
        .sheet(isPresented: $isPresentingAddSheet) {
            Color.clear
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                guard newValue == .add else {
                    selection = newValue
                    return
                }

                isPresentingAddSheet = true
            }
        )
    }

    @available(iOS 18.0, *)
    private var modernTabView: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house", value: .home) {
                DashboardView()
            }

            Tab("Transactions", systemImage: "list.bullet.rectangle", value: .transactions) {
                TransactionsView()
            }

            Tab("Assistant", systemImage: "sparkles", value: .assistant) {
                AssistantView()
            }

            Tab(
                "Add",
                systemImage: "plus",
                value: .add,
                role: .search
            ) {
                Color.clear
            }
        }
    }

    private var legacyTabView: some View {
        TabView(selection: tabSelection) {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

            TransactionsView()
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet.rectangle")
                }
                .tag(AppTab.transactions)

            AssistantView()
                .tabItem {
                    Label("Assistant", systemImage: "sparkles")
                }
                .tag(AppTab.assistant)

            Color.clear
                .tabItem {
                    Label("Add", systemImage: "plus")
                }
                .tag(AppTab.add)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AccountStore())
}
