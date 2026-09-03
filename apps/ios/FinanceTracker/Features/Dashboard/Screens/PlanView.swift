import SwiftUI

struct PlanView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @StateObject private var summaryRates = ExchangeRateStore()
    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var reportingCurrency = AppPreferences.initialCurrency
    @State private var selectedMonth = BudgetMonth.start(of: .now)
    @State private var isShowingBudgetSettings = false
    @State private var editingUpcomingTransaction: UpcomingTransaction?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FinancePageHeader(title: "Plan")
                    summaryContent
                }
                .modifier(FinanceSectionMargins())

                if budgetIsLoaded, let budget = convertedBudget, let transactions = monthTransactions,
                   transactionStore.state == .loaded {
                    let pools = BudgetLimitProgress.pools(budget: budget, transactions: transactions)
                    let categories = BudgetLimitProgress.categories(
                        budget: budget, transactions: transactions, categories: transactionStore.categories
                    )
                    if !pools.isEmpty { limitsSection("Budget pools", rows: pools) }
                    if !categories.isEmpty { limitsSection("Category limits", rows: categories) }
                }

                ComingUpSection(allAccounts: true) { editingUpcomingTransaction = $0 }
                    .modifier(FinanceSectionMargins())
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(4))
            .environment(\.defaultMinListRowHeight, 0)
            .navigationBarTitleDisplayMode(.inline)
            .financeMonthPickerToolbar(month: $selectedMonth)
            .refreshable { await reload() }
        }
        .task(id: selectedMonth) {
            await budgetStore.loadBudget(month: selectedMonth, accountID: nil)
        }
        .task { await transactionStore.loadCategories() }
        .task(id: rateScope) { await loadRates() }
        .sheet(isPresented: $isShowingBudgetSettings) {
            BudgetSettingsView(month: selectedMonth, accountID: nil, currency: currency, budget: convertedBudget)
                .environmentObject(summaryRates)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingUpcomingTransaction) { transaction in
            AddTransactionView(upcomingTransaction: transaction)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        if case let .failed(message) = budgetStore.state {
            VStack(alignment: .leading, spacing: 12) {
                Text("Couldn’t load budget").font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                PrimaryActionButton("Try Again", appearance: .prominent) {
                    Task { await budgetStore.loadBudget(month: selectedMonth, accountID: nil, force: true) }
                }
            }
            .padding(.vertical, 12)
        } else if !budgetIsLoaded {
            ProgressView("Loading budget").frame(maxWidth: .infinity).padding(.vertical, 24)
                .listRowBackground(Color.clear)
        } else if budgetStore.budget == nil {
            setupBudget
        } else if let budget = convertedBudget {
            if let limit = budget.monthlyLimit.flatMap({ Decimal(string: $0) }), limit > 0 {
                if transactionStore.state == .loaded, let insights,
                   let interval = Calendar.current.dateInterval(of: .month, for: selectedMonth) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        if let summary = MonthlySummaryState(
                            monthlyBudget: limit, amountSpent: insights.spent, currentDate: context.date,
                            startOfMonth: interval.start, endOfMonth: interval.end, currency: currency, locale: locale
                        ) {
                            Button { isShowingBudgetSettings = true } label: {
                                MonthlySummaryCompactView(
                                    state: summary, showsPlannedBills: true,
                                    plannedBills: forecast(for: summary),
                                    isLoadingPlannedBills: transactionStore.upcomingState == .loading || transactionStore.upcomingState == .idle
                                )
                            }
                            .buttonStyle(MonthlySummaryButtonStyle())
                            .accessibilityHint("Open budget settings")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    FinanceSummaryUnavailable(state: transactionStore.state, rateState: summaryRates.state)
                }
            } else {
                setupBudget
            }
        } else {
            FinanceSummaryUnavailable(state: .loaded, rateState: summaryRates.state)
        }
    }

    private var setupBudget: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(budgetStore.budget == nil ? "Set up your budget" : "Set a monthly limit")
                .font(.title3.weight(.semibold))
            Text("Choose a monthly spending limit to see what remains after planned bills.")
                .font(.subheadline).foregroundStyle(.secondary)
            PrimaryActionButton(budgetStore.budget == nil ? "Set up budget" : "Set monthly limit", appearance: .prominent) {
                isShowingBudgetSettings = true
            }
        }
        .padding(.vertical, 12)
    }

    private func limitsSection(_ title: String, rows: [BudgetLimitProgress]) -> some View {
        Section {
            ForEach(rows) { row in
                Button { isShowingBudgetSettings = true } label: {
                    BudgetLimitRow(progress: row, currency: currency)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit budget limits")
            }
        } header: {
            FinanceSectionHeader(title) {
                Button("Edit") { isShowingBudgetSettings = true }
            }
        }
        .modifier(FinanceSectionMargins())
    }

    private var currency: String { reportingCurrency.uppercased() }
    private var budgetIsLoaded: Bool { budgetStore.isLoaded(month: selectedMonth, accountID: nil) }
    private var convertedBudget: MonthlyBudget? {
        guard budgetIsLoaded else { return nil }
        return budgetStore.budget?.converted(to: currency, using: summaryRates)
    }
    private var convertedTransactions: [FinanceTransaction]? {
        FinanceOverviewData.converted(transactionStore.allTransactions, to: currency, using: summaryRates)
    }
    private var monthTransactions: [FinanceTransaction]? {
        convertedTransactions.map { FinanceOverviewData.transactions($0, in: selectedMonth) }
    }
    private var insights: DashboardInsights? {
        convertedTransactions.map {
            DashboardInsights.calculate(transactions: $0, month: selectedMonth,
                                        monthlyLimit: convertedBudget?.monthlyLimit.flatMap { Decimal(string: $0) })
        }
    }
    private var currencies: Set<String> {
        Set(transactionStore.allTransactions.map(\.currency)
            + transactionStore.allUpcomingTransactions.map(\.currency)
            + [budgetStore.budget?.currency].compactMap { $0 })
    }
    private var rateScope: String { "\(currency):\(currencies.sorted().joined(separator: ","))" }
    private func forecast(for summary: MonthlySummaryState) -> PlannedBillsSummary? {
        guard transactionStore.upcomingState == .loaded else { return nil }
        return PlannedBillsSummary.calculate(
            summary: summary, transactions: transactionStore.allTransactions,
            upcoming: transactionStore.allUpcomingTransactions
        ) { amount, sourceCurrency in
            summaryRates.convert(amount, from: sourceCurrency, to: currency)
        }
    }
    private func loadRates(force: Bool = false) async {
        await summaryRates.load(currencies: currencies, reportingCurrency: currency, force: force)
    }
    private func reload() async {
        async let transactions: Void = transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        async let budget: Void = budgetStore.loadBudget(month: selectedMonth, accountID: nil, force: true)
        _ = await (transactions, budget)
        await loadRates(force: true)
    }
}
