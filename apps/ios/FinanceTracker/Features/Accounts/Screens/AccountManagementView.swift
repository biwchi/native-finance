import SwiftUI

struct AccountManagementView: View {
    private let selection: Binding<UUID?>?
    private let allowsAllAccounts: Bool
    let onBottomActionBarHeightChange: (CGFloat) -> Void
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

    init(
        selection: Binding<UUID?>? = nil,
        allowsAllAccounts: Bool = true,
        onBottomActionBarHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.selection = selection
        self.allowsAllAccounts = allowsAllAccounts
        self.onBottomActionBarHeightChange = onBottomActionBarHeightChange
    }

    var body: some View {
        NavigationStack {
            AppList {
                if allowsAllAccounts, !editMode.isEditing {
                    AppSection {
                        allAccountsButton
                    }
                }

                AppSection {
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
                }
            }
            .animateListChanges(value: accountStore.accounts.map(\.id))
            .listStyle(.insetGrouped)
            .environment(\.editMode, $editMode)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isBusy)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Group {
                        Button(editMode.isEditing ? "Done" : "Edit") {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                        }
                        .disabled(accountStore.accounts.isEmpty || isBusy)
                    }
                    .legacyToolbarControl()
                }

                ToolbarItem(placement: .cancellationAction) {
                    Group {
                        Button {
                            dismiss()
                        } label: {
                            AppIcon("xmark", size: AppControlSize.iconButtonGlyph)
                        }
                        .accessibilityLabel("Close")
                        .disabled(isBusy)
                    }
                    .legacyToolbarIcon()
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton("Add Account") {
                    editor = .add
                }
                .disabled(isBusy)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .reportScanDraftBottomBarHeight(onBottomActionBarHeightChange)
            }
        }
        .presentationDetents([.large])
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
        .appSheet(item: $editor) { destination in
            AccountEditorView(account: destination.account) { account in
                if destination.account == nil {
                    selection?.wrappedValue = account.id
                }
            }
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
                        "This also deletes its transactions, goals, and account budget data. This can't be undone."
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
                isSelected: selectedAccountID == account.id,
                isEditing: editMode.isEditing
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityAddTraits(
            !editMode.isEditing && selectedAccountID == account.id
                ? .isSelected : []
        )
        .accessibilityHint(
            editMode.isEditing ? "Edit account details" : "Select account and close"
        )
        .circleSwipeActions(isEnabled: !isBusy && !editMode.isEditing) {
            CircleSwipeAction(title: "Delete", icon: "trash") {
                presentedAlert = .confirmDeletion(account)
            }
            CircleSwipeAction(title: "Edit", icon: "edit-pencil", tint: .gray) {
                editor = .edit(account)
            }
        }
    }

    private var allAccountsButton: some View {
        Button {
            selectAccount(nil)
        } label: {
            HStack(spacing: 12) {
                AccountIconBadge(iconName: "credit-cards", color: AppColor.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("All Accounts")

                    Text(balanceSubtitle(for: nil))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                if selectedAccountID == nil {
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
        .accessibilityAddTraits(selectedAccountID == nil ? .isSelected : [])
        .accessibilityHint("Show all accounts and close")
    }

    private var isBusy: Bool {
        isUpdatingOrder || deletingAccountID != nil
    }

    private var selectedAccountID: UUID? {
        if let selection { return selection.wrappedValue }
        return accountStore.selectedAccountID
    }

    private func balanceSubtitle(for account: Account?) -> String {
        if let balance = transactionStore.balance(
            accountID: account?.id,
            currency: account?.currency ?? reportingCurrency.uppercased(),
            rates: exchangeRateStore.snapshot
        ) {
            MoneyFormatter.format(
                balance, currency: account?.currency ?? reportingCurrency.uppercased(),
                roundToWhole: roundTotals
            )

        } else {
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
        if let selection {
            selection.wrappedValue = accountID
        } else {
            accountStore.selectedAccountID = accountID
        }
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
            if selection?.wrappedValue == account.id {
                selection?.wrappedValue = nil
            }
            await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        } catch {
            presentedAlert = .error(error.localizedDescription)
        }
    }
}
