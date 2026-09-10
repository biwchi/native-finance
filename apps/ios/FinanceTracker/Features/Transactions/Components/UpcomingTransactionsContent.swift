import SwiftUI

struct UpcomingTransactionsContent: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore

    var limit: Int? = nil
    var allAccounts = false
    var kindFilter: TransactionKind? = nil
    var isDeleting = false
    let onEdit: (UpcomingTransaction) -> Void
    var onDelete: ((UpcomingTransaction) -> Void)? = nil

    var body: some View {
        ForEach(transactions.prefix(limit ?? Int.max)) { transaction in
            transactionButton(transaction)
        }
    }

    private var transactions: [UpcomingTransaction] {
        let transactions = allAccounts ? transactionStore.allUpcomingTransactions : transactionStore.upcomingTransactions(for: accountStore.selectedAccountID)
        return transactions.filter { kindFilter == nil || $0.kind == kindFilter }
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
        .circleSwipeActions(isEnabled: !isDeleting) {
            if let onDelete {
                CircleSwipeAction(title: "Delete", icon: "trash") {
                    onDelete(transaction)
                }
            }
        }
    }
}
