import SwiftUI

struct UpcomingTransactionsContent: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore

    var limit: Int? = nil
    var allAccounts = false
    var isDeleting = false
    let onEdit: (UpcomingTransaction) -> Void
    var onDelete: ((UpcomingTransaction) -> Void)? = nil

    var body: some View {
        switch transactionStore.upcomingState {
        case .idle, .loading:
            ProgressView("Loading recurring transactions")
                .frame(maxWidth: .infinity)
        case .loaded:
            ForEach((allAccounts ? transactionStore.allUpcomingTransactions : transactionStore.upcomingTransactions).prefix(limit ?? Int.max)) { transaction in
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
