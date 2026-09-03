import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @StateObject private var summaryRates = ExchangeRateStore()
    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var reportingCurrency = AppPreferences.initialCurrency
    @State private var selectedMonth = BudgetMonth.start(of: .now)
    @State private var editingTransaction: FinanceTransaction?
    @State private var editingUpcomingTransaction: UpcomingTransaction?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FinancePageHeader(title: "Overview")
                    if transactionStore.state == .loaded, let insights {
                        MonthlySummaryCard(
                            monthTitle: "Total spent",
                            titleColor: AppColor.accent,
                            surface: .glass
                        ) {} content: {
                            MonthlySummaryAmount(amount: MoneyFormatter.format(insights.spent, currency: currency))
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        FinanceMetricCards(
                            first: .init(title: "Income", amount: insights.income),
                            second: .init(
                                title: "Net",
                                amount: insights.net,
                                signed: true,
                                amountColor: AppColor.positive
                            ),
                            currency: currency,
                            surface: .glass
                        )
                    } else {
                        FinanceSummaryUnavailable(state: transactionStore.state, rateState: summaryRates.state)
                    }
                }
                .modifier(FinanceSectionMargins())
                recentTransactionsSection.modifier(FinanceSectionMargins())
                ComingUpSection { editingUpcomingTransaction = $0 }
                    .modifier(FinanceSectionMargins())
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(4))
            .environment(\.defaultMinListRowHeight, 0)
            .leadingAccountSelectorToolbar()
            .financeMonthPickerToolbar(month: $selectedMonth)
            .refreshable { await reload() }
        }
        .task(id: rateScope) { await loadRates() }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(transaction: transaction)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingUpcomingTransaction) { transaction in
            AddTransactionView(upcomingTransaction: transaction)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var currency: String { accountStore.selectedAccount?.currency ?? reportingCurrency.uppercased() }
    private var currencies: Set<String> { Set(transactionStore.transactions.map(\.currency)) }
    private var rateScope: String { "\(currency):\(currencies.sorted().joined(separator: ","))" }
    private var monthTransactions: [FinanceTransaction] {
        FinanceOverviewData.transactions(transactionStore.transactions, in: selectedMonth)
    }
    private var insights: DashboardInsights? {
        guard let converted = FinanceOverviewData.converted(transactionStore.transactions, to: currency, using: summaryRates) else { return nil }
        return DashboardInsights.calculate(transactions: converted, month: selectedMonth, monthlyLimit: nil)
    }
    private func loadRates(force: Bool = false) async {
        await summaryRates.load(currencies: currencies, reportingCurrency: currency, force: force)
    }
    private func reload() async {
        await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        await loadRates(force: true)
    }

    private var recentTransactionsSection: some View {
        Section {
            switch transactionStore.state {
            case .idle, .loading:
                ProgressView("Loading transactions")
                    .frame(maxWidth: .infinity)
            case .loaded:
                if monthTransactions.isEmpty {
                    ContentUnavailableView(
                        "No transactions",
                        iconName: "calendar-minus",
                        description: Text("Transactions for the selected month will appear here.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(monthTransactions.prefix(4)) { transaction in
                        Button {
                            editingTransaction = transaction
                        } label: {
                            TransactionRow(
                                transaction: transaction,
                                account: accountStore.accounts.first { $0.id == transaction.accountId }
                            )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit transaction")
                    }
                }
            case .failed:
                Label("Couldn’t load transactions", icon: "wifi-warning")
                    .foregroundStyle(.secondary)
            }
        } header: {
            FinanceSectionHeader("Recent activity") {
                NavigationLink {
                    TransactionListView(showsOverview: true, month: selectedMonth)
                } label: {
                    Text("See all")
                }
                .accessibilityLabel("See all transactions")
            }
            .listRowInsets(EdgeInsets(top: AppSpacing.medium, leading: AppSpacing.large, bottom: 0, trailing: AppSpacing.large))
        }
    }

}
