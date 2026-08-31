import Foundation
import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore

    var body: some View {
        NavigationStack {
            Group {
                switch transactionStore.state {
                case .idle, .loading:
                    ProgressView("Loading transactions")

                case .loaded where transactionStore.transactions.isEmpty:
                    ContentUnavailableView(
                        "No transactions",
                        systemImage: "list.bullet.rectangle",
                        description: Text(emptyDescription)
                    )

                case .loaded:
                    List(transactionStore.transactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await transactionStore.loadTransactions(
                            accountID: accountStore.selectedAccountID
                        )
                    }

                case let .failed(message):
                    ContentUnavailableView {
                        Label("Couldn’t load transactions", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await transactionStore.loadTransactions(
                                    accountID: accountStore.selectedAccountID
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Transactions")
            .accountSelectorToolbar()
        }
        .task(id: accountStore.selectedAccountID) {
            await transactionStore.loadTransactions(
                accountID: accountStore.selectedAccountID
            )
        }
    }

    private var emptyDescription: String {
        if let account = accountStore.selectedAccount {
            "Transactions for \(account.name) will appear here."
        } else {
            "Transactions from all accounts will appear here."
        }
    }
}

struct TransactionRow: View {
    let transaction: FinanceTransaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.kind == .income ? "arrow.down" : "arrow.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(transaction.kind == .income ? .green : .red)
                .frame(width: 36, height: 36)
                .background(.quaternary, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let amount = Decimal(string: transaction.amount) {
                Text(
                    transaction.kind == .income ? amount : -amount,
                    format: .currency(code: transaction.currency)
                )
                .font(.body.monospacedDigit().weight(.semibold))
            } else {
                Text(transaction.amount)
                    .font(.body.monospacedDigit().weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        if let description = transaction.description, !description.isEmpty {
            description
        } else if let category = transaction.category {
            category.name
        } else {
            transaction.kind.title
        }
    }

    private var subtitle: String {
        let date = transaction.occurredAt.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .year()
                .hour()
                .minute()
        )

        if transaction.description?.isEmpty == false,
           let category = transaction.category {
            return "\(category.name) · \(date)"
        }

        return date
    }
}

#Preview {
    TransactionsView()
        .environmentObject(AccountStore())
        .environmentObject(TransactionStore())
}
