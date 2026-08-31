import Combine
import Foundation
import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @StateObject private var viewModel = TransactionsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading transactions")

                case .loaded where viewModel.transactions.isEmpty:
                    ContentUnavailableView(
                        "No transactions",
                        systemImage: "list.bullet.rectangle",
                        description: Text(emptyDescription)
                    )

                case .loaded:
                    List(viewModel.transactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.load(accountID: accountStore.selectedAccountID)
                    }

                case let .failed(message):
                    ContentUnavailableView {
                        Label("Couldn’t load transactions", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await viewModel.load(accountID: accountStore.selectedAccountID)
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
            await viewModel.load(accountID: accountStore.selectedAccountID)
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

                Text(transaction.occurredOn)
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
        if let category = transaction.category, !category.isEmpty {
            category
        } else {
            transaction.kind == .income ? "Income" : "Expense"
        }
    }
}

@MainActor
final class TransactionsViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transactions: [FinanceTransaction] = []

    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func load(accountID: UUID?) async {
        state = .loading

        do {
            let transactions = try await apiClient.transactions(accountID: accountID)
            guard !Task.isCancelled else { return }

            self.transactions = transactions
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    TransactionsView()
        .environmentObject(AccountStore())
}
