import SwiftUI

struct AccountManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var reportingCurrency = AppPreferences.initialCurrency
    @StateObject private var exchangeRateStore = ExchangeRateStore()

    @State private var editor: AccountEditorDestination?
    @State private var presentedAlert: AccountManagementAlert?
    @State private var isUpdatingOrder = false
    @State private var deletingAccountID: UUID?
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            List {
                if !editMode.isEditing {
                    Section {
                        allAccountsButton
                    }
                }

                Section {
                    if accountStore.accounts.isEmpty {
                        ContentUnavailableView(
                            "No accounts",
                            iconName: "credit-card",
                            description: Text("Add an account to start tracking transactions.")
                        )
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(accountStore.accounts) { account in
                            accountButton(for: account)
                        }
                        .onMove(perform: moveAccounts)
                        .onDelete(perform: requestDeletion)
                        .moveDisabled(isUpdatingOrder || deletingAccountID != nil)
                        .deleteDisabled(isUpdatingOrder || deletingAccountID != nil)
                    }
                } footer: {
                    if !accountStore.accounts.isEmpty {
                        Text(
                            editMode.isEditing
                                ? "Tap an account to edit it. Use the row controls to reorder or remove accounts."
                                : "Tap an account to select it. Swipe left to edit or delete. Use Edit to reorder accounts."
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, $editMode)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isBusy)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                    .disabled(accountStore.accounts.isEmpty || isBusy)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(isBusy)
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        editor = .add
                    } label: {
                        Label("Add Account", icon: "plus")
                    }
                    .disabled(isBusy)
                }
            }
        }
        .onChange(of: accountStore.accounts.isEmpty) { _, isEmpty in
            if isEmpty {
                editMode = .inactive
            }
        }
        .task(id: exchangeRateScopeKey) {
            await exchangeRateStore.load(
                currencies: exchangeCurrencies,
                reportingCurrency: reportingCurrency.uppercased()
            )
        }
        .sheet(item: $editor) { destination in
            AccountEditorView(account: destination.account)
                .environmentObject(accountStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case let .confirmDeletion(account):
                Alert(
                    title: Text("Delete \(account.name)?"),
                    message: Text(
                        "This also deletes its transactions and account budget data. This can't be undone."
                    ),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            await deleteAccount(account)
                        }
                    },
                    secondaryButton: .cancel()
                )
            case let .error(message):
                Alert(
                    title: Text("Couldn't update accounts"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func accountButton(for account: Account) -> some View {
        Button {
            if editMode.isEditing {
                editor = .edit(account)
            } else {
                selectAccount(account.id)
            }
        } label: {
            AccountManagementRow(
                account: account,
                balanceSubtitle: balanceSubtitle(for: account),
                isWorking: deletingAccountID == account.id,
                isSelected: accountStore.selectedAccountID == account.id,
                isEditing: editMode.isEditing
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityAddTraits(
            !editMode.isEditing && accountStore.selectedAccountID == account.id
                ? .isSelected : []
        )
        .accessibilityHint(
            editMode.isEditing ? "Edit account details" : "Select account and close"
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !editMode.isEditing {
                Button(role: .destructive) {
                    presentedAlert = .confirmDeletion(account)
                } label: {
                    Label("Delete", icon: "trash")
                }
                .disabled(isBusy)

                Button {
                    editor = .edit(account)
                } label: {
                    Label("Edit", icon: "edit-pencil")
                }
                .tint(.gray)
                .disabled(isBusy)
            }
        }
    }

    private var allAccountsButton: some View {
        Button {
            selectAccount(nil)
        } label: {
            HStack(spacing: 12) {
                AppIcon("credit-cards", size: 17)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("All Accounts")

                    Text(balanceSubtitle(for: nil))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                if accountStore.selectedAccountID == nil {
                    AppIcon("check", size: 17)
                        .foregroundStyle(AppColor.accent)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityAddTraits(accountStore.selectedAccountID == nil ? .isSelected : [])
        .accessibilityHint("Show all accounts and close")
    }

    private var isBusy: Bool {
        isUpdatingOrder || deletingAccountID != nil
    }

    private func balanceSubtitle(for account: Account?) -> String {
        switch transactionStore.state {
        case .idle, .loading:
            "Loading balance"
        case .loaded:
            if let balance = transactionStore.balance(
                accountID: account?.id,
                currency: account?.currency ?? reportingCurrency.uppercased(),
                rates: exchangeRateStore.snapshot
            ) {
                MoneyFormatter.format(
                    balance, currency: account?.currency ?? reportingCurrency.uppercased(),
                    roundToWhole: roundTotals
                )
            } else if exchangeRateStore.state == .idle || exchangeRateStore.state == .loading {
                "Converting balance"
            } else {
                "Balance unavailable"
            }
        case .failed:
            "Balance unavailable"
        }
    }

    private var exchangeCurrencies: Set<String> {
        Set(accountStore.accounts.map(\.currency) + transactionStore.allTransactions.map(\.currency))
    }

    private var exchangeRateScopeKey: String {
        "\(reportingCurrency.uppercased()):\(exchangeCurrencies.sorted().joined(separator: ","))"
    }

    private func selectAccount(_ accountID: UUID?) {
        accountStore.selectedAccountID = accountID
        dismiss()
    }

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        var reorderedAccounts = accountStore.accounts
        reorderedAccounts.move(fromOffsets: source, toOffset: destination)
        isUpdatingOrder = true

        Task {
            defer { isUpdatingOrder = false }

            do {
                try await accountStore.reorderAccounts(reorderedAccounts)
            } catch {
                presentedAlert = .error(error.localizedDescription)
            }
        }
    }

    private func requestDeletion(at offsets: IndexSet) {
        guard let index = offsets.first,
              accountStore.accounts.indices.contains(index) else {
            return
        }
        presentedAlert = .confirmDeletion(accountStore.accounts[index])
    }

    private func deleteAccount(_ account: Account) async {
        deletingAccountID = account.id
        defer { deletingAccountID = nil }

        do {
            try await accountStore.deleteAccount(account)
            await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        } catch {
            presentedAlert = .error(error.localizedDescription)
        }
    }
}
