import SwiftUI

struct BudgetTransactionsView: View {
    enum Scope {
        case all
        case pool(UUID)
        case category(UUID)
    }

    let title: String
    let scope: Scope
    let month: Date
    let accountID: UUID?
    let currency: String
    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var transactionStore: TransactionStore
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @EnvironmentObject private var rates: ExchangeRateStore
    @State private var editingTransaction: FinanceTransaction?

    var body: some View {
        List {
            Section {
                if transactionStore.state == .loaded,
                   let converted = FinanceOverviewData.converted(transactions, to: currency, using: rates) {
                    FinanceHighlightCard(
                        title: "Spent", amount: converted.reduce(Decimal.zero) { $0 + (Decimal(string: $1.amount) ?? 0) },
                        currency: currency, detail: month.formatted(.dateTime.month(.wide).year())
                    ) {
                        Text("\(transactions.count) \(transactions.count == 1 ? "transaction" : "transactions")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    FinanceSummaryUnavailable(state: transactionStore.state, rateState: rates.state)
                }
            }
            .modifier(FinanceSectionMargins())
            Section("Transactions") {
                switch transactionStore.state {
                case .idle, .loading:
                    ProgressView("Loading transactions").frame(maxWidth: .infinity)
                case .failed:
                    Button("Try Again") { Task { await refresh() } }
                case .loaded:
                    if transactions.isEmpty {
                        ContentUnavailableView("No spending here", iconName: "list",
                            description: Text("Transactions for this budget will appear here."))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(transactions) { transaction in
                        Button { editingTransaction = transaction } label: {
                            TransactionRow(
                                transaction: transaction,
                                account: accountStore.accounts.first { $0.id == transaction.accountId },
                                timestampStyle: .dateAndTime
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit transaction")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(AppSpacing.large))
        .financePage(usesNativeNavigationTitle: true)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await refresh() }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(transaction: transaction)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var transactions: [FinanceTransaction] {
        let expenses = transactionStore.allTransactions.filter {
            $0.kind == .expense && (accountID == nil || $0.accountId == accountID)
        }
        let monthly = FinanceOverviewData.transactions(expenses, in: month, calendar: calendar)
        switch scope {
        case .all: return monthly
        case .pool(let id):
            guard let budget = budgetStore.budget else { return [] }
            return BudgetLimitProgress.transactions(inPool: id, budget: budget, from: monthly)
        case .category(let id):
            return BudgetLimitProgress.transactions(inCategory: id, from: monthly)
        }
    }

    private func refresh() async {
        await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        await rates.load(currencies: Set(transactions.map(\.currency)), reportingCurrency: currency, force: true)
    }
}
