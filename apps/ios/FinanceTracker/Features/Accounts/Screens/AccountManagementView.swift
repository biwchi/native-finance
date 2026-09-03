import SwiftUI

struct AccountManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore

    @State private var editor: AccountEditorDestination?
    @State private var presentedAlert: AccountManagementAlert?
    @State private var isUpdatingOrder = false
    @State private var deletingAccountID: UUID?

    var body: some View {
        NavigationStack {
            List {
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
                            Button {
                                editor = .edit(account)
                            } label: {
                                AccountManagementRow(
                                    account: account,
                                    isWorking: deletingAccountID == account.id
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isUpdatingOrder || deletingAccountID != nil)
                        }
                        .onMove(perform: moveAccounts)
                        .onDelete(perform: requestDeletion)
                        .moveDisabled(isUpdatingOrder || deletingAccountID != nil)
                        .deleteDisabled(isUpdatingOrder || deletingAccountID != nil)
                    }
                } footer: {
                    if !accountStore.accounts.isEmpty {
                        Text("Tap an account to edit it. Use Edit to reorder or remove accounts.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isBusy)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(accountStore.accounts.isEmpty || isBusy)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
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
        .sheet(item: $editor) { destination in
            AccountEditorView(account: destination.account)
                .environmentObject(accountStore)
                .presentationDetents([.medium, .large])
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

    private var isBusy: Bool {
        isUpdatingOrder || deletingAccountID != nil
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
