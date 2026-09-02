import SwiftUI

struct RecurringTransactionsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @State private var editingTransaction: UpcomingTransaction?
    @State private var deletingTransaction: UpcomingTransaction?
    @State private var deletingTransactionID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if transactionStore.upcomingState != .loaded || !transactionStore.upcomingTransactions.isEmpty {
                Section("Coming up") {
                    UpcomingTransactionsContent(
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
        .accountSelectorToolbar()
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

struct UpcomingTransactionsContent: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore

    var limit: Int? = nil
    var isDeleting = false
    let onEdit: (UpcomingTransaction) -> Void
    var onDelete: ((UpcomingTransaction) -> Void)? = nil

    var body: some View {
        switch transactionStore.upcomingState {
        case .idle, .loading:
            ProgressView("Loading recurring transactions")
                .frame(maxWidth: .infinity)
        case .loaded:
            ForEach(transactionStore.upcomingTransactions.prefix(limit ?? Int.max)) { transaction in
                transactionButton(transaction)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 12) {
                Label("Couldn’t load recurring transactions", icon: "wifi-warning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                PrimaryActionButton("Try Again") {
                    Task {
                        await transactionStore.loadUpcomingTransactions(
                            accountID: accountStore.selectedAccountID
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func transactionButton(_ transaction: UpcomingTransaction) -> some View {
        let account = accountStore.accounts.first { $0.id == transaction.accountId }
        return Button {
            onEdit(transaction)
        } label: {
            TransactionRow(
                transaction: transaction,
                account: account,
                titleOverride: transaction.title,
                recurrenceDetails: "\(transaction.frequency.title) · \(transaction.occurredAt.formatted(date: .abbreviated, time: .omitted))",
                style: .upcoming
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit recurring transaction")
        .disabled(isDeleting)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete(transaction)
                } label: {
                    Label("Delete", icon: "trash")
                }
                .disabled(isDeleting)
            }
        }
    }
}

struct RecurringDeletionActions: View {
    let onAction: (RecurringDeletionAction) -> Void

    var body: some View {
        Button(RecurringDeletionAction.occurrence.title) { onAction(.occurrence) }
        Button(RecurringDeletionAction.stopRepeating.title) { onAction(.stopRepeating) }
        Button(RecurringDeletionAction.occurrenceAndFuture.title, role: .destructive) { onAction(.occurrenceAndFuture) }
        Button("Cancel", role: .cancel) {}
    }
}
