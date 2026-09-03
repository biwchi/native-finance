import SwiftUI

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
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
                    FinanceMonthHeader(title: "Overview", month: $selectedMonth)
                    if transactionStore.state == .loaded, let insights {
                        MonthlySummaryCard(monthTitle: "Total spent") {} content: {
                            MonthlySummaryAmount(amount: MoneyFormatter.format(insights.spent, currency: currency))
                        }
                        .environment(\.monthlySummaryCardBackground, summaryBackground)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        FinanceMetricCards(
                            first: .init(title: "Income", amount: insights.income),
                            second: .init(title: "Net", amount: insights.net, signed: true),
                            currency: currency
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
    private var summaryBackground: Color {
        colorScheme == .dark
            ? Color(red: 43 / 255, green: 33 / 255, blue: 20 / 255)
            : Color(red: 1, green: 240 / 255, blue: 215 / 255)
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
            HStack {
                Text("Recent activity")

                Spacer()

                NavigationLink {
                    TransactionListView(showsOverview: true, month: selectedMonth)
                } label: {
                    Text("See all")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
                .accessibilityLabel("See all transactions")
            }
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
        }
    }

}

#Preview("Dashboard") {
    DashboardView()
        .environmentObject(
            AccountStore.preview(
                accounts: [DashboardPreviewData.account],
                selectedAccountID: DashboardPreviewData.account.id
            )
        )
        .environmentObject(BudgetStore.preview(DashboardPreviewData.budget))
        .environmentObject(ExchangeRateStore())
        .environmentObject(
            TransactionStore.preview(transactions: DashboardPreviewData.transactions)
        )
        .preferredColorScheme(.dark)
}

private enum DashboardPreviewData {
    static let now = Date.now
    static let account = Account(
        id: UUID(),
        name: "Everyday card",
        type: .checking,
        currency: "KZT",
        icon: "credit-card",
        iconColor: .blue,
        createdAt: "",
        updatedAt: ""
    )

    static let budget = MonthlyBudget(
        id: UUID(),
        accountId: account.id,
        month: BudgetMonth.key(for: now),
        currency: account.currency,
        monthlyLimit: "1200000",
        groups: [],
        categoryAssignments: [],
        createdAt: now,
        updatedAt: now
    )

    static let food = category(
        systemKey: "expense.food-drink",
        name: "Food & Drink",
        icon: "cutlery",
        color: .orange
    )
    static let housing = category(
        systemKey: "expense.housing",
        name: "Housing",
        icon: "home-simple",
        color: .blue
    )
    static let shopping = category(
        systemKey: "expense.shopping",
        name: "Shopping",
        icon: "shopping-bag",
        color: .purple
    )
    static let salary = TransactionCategory(
        id: UUID(),
        systemKey: "income.salary",
        name: "Salary",
        kind: .income,
        icon: "cash",
        color: .green,
        isSystem: true,
        examples: nil,
        sortOrder: nil,
        createdAt: now,
        updatedAt: now
    )

    static let transactions = [
        transaction(
            kind: .expense,
            amount: "520000",
            category: housing
        ),
        transaction(
            kind: .expense,
            amount: "310000",
            category: food
        ),
        transaction(
            kind: .expense,
            amount: "195265.84",
            category: shopping
        ),
        transaction(
            kind: .income,
            amount: "2400000",
            category: salary
        ),
    ]

    private static func category(
        systemKey: String,
        name: String,
        icon: String,
        color: CategoryColor
    ) -> TransactionCategory {
        TransactionCategory(
            id: UUID(),
            systemKey: systemKey,
            name: name,
            kind: .expense,
            icon: icon,
            color: color,
            isSystem: true,
            examples: nil,
            sortOrder: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func transaction(
        kind: TransactionKind,
        amount: String,
        category: TransactionCategory
    ) -> FinanceTransaction {
        FinanceTransaction(
            id: UUID(),
            accountId: account.id,
            kind: kind,
            amount: amount,
            currency: account.currency,
            category: category,
            note: nil,
            occurredAt: now,
            createdAt: now,
            updatedAt: now
        )
    }
}
