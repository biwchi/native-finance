import SwiftUI

struct RecurringTransactionsView: View {
    var allAccounts = false
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @State private var editingTransaction: UpcomingTransaction?
    @State private var deletingTransaction: UpcomingTransaction?
    @State private var deletingTransactionID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if transactionStore.upcomingState != .loaded || !upcomingTransactions.isEmpty {
                Section("Coming up") {
                    UpcomingTransactionsContent(
                        allAccounts: allAccounts,
                        isDeleting: deletingTransactionID != nil,
                        onEdit: { editingTransaction = $0 },
                        onDelete: { deletingTransaction = $0 }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Recurring transactions")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(RecurringAccountsToolbar(allAccounts: allAccounts))
        .refreshable {
            await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(upcomingTransaction: transaction)
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(errorMessage == nil ? "Choose an action" : "Couldn’t update recurring transaction", isPresented: alertBinding) {
            if errorMessage != nil {
                Button("OK", role: .cancel) {}
            } else if let transaction = deletingTransaction {
                RecurringDeletionActions { action in
                    Task { await delete(transaction, action: action) }
                }
            }
        } message: {
            Text(errorMessage ?? "This is a recurring transaction. What would you like to delete?")
        }
    }

    private var upcomingTransactions: [UpcomingTransaction] {
        allAccounts ? transactionStore.allUpcomingTransactions : transactionStore.upcomingTransactions
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { deletingTransaction != nil || errorMessage != nil },
            set: {
                if !$0 {
                    deletingTransaction = nil
                    errorMessage = nil
                }
            }
        )
    }

    private func delete(_ transaction: UpcomingTransaction, action: RecurringDeletionAction) async {
        deletingTransactionID = transaction.id
        defer { deletingTransactionID = nil }
        do {
            try await transactionStore.deleteUpcomingTransaction(transaction, action: action)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
