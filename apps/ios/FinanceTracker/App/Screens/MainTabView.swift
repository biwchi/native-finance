import SwiftUI

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
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            QuickAccountMenu(
                accounts: accountStore.accounts,
                selectedAccountID: quickEntryAccountID
            ) { accountID in
                quickEntryAccountID = accountID
            }

            HStack(alignment: .top, spacing: AppSpacing.small) {
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
                    AppColor.controlFill,
                    in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
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
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.small)
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
