import SwiftUI

struct ComingUpSection: View {
    @EnvironmentObject private var transactionStore: TransactionStore
    var allAccounts = false
    let onEdit: (UpcomingTransaction) -> Void

    private var transactions: [UpcomingTransaction] {
        allAccounts ? transactionStore.allUpcomingTransactions : transactionStore.upcomingTransactions
    }

    var body: some View {
        if transactionStore.upcomingState == .loaded, !transactions.isEmpty {
            Section {
                UpcomingTransactionsContent(limit: 4, allAccounts: allAccounts, onEdit: onEdit)
            } header: {
                FinanceSectionHeader("Coming up") {
                    NavigationLink {
                        RecurringTransactionsView(allAccounts: allAccounts)
                    } label: {
                        Text("See all")
                    }
                    .accessibilityLabel("See all recurring transactions")
                }
                .listRowInsets(EdgeInsets(top: AppSpacing.medium, leading: AppSpacing.large, bottom: 0, trailing: AppSpacing.large))
            }
        }
    }
}
