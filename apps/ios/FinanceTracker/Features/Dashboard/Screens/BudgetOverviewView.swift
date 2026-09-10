import SwiftUI

struct BudgetOverviewView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @AppStorage(AppPreferences.defaultCurrencyKey) private var reportingCurrency = AppPreferences.initialCurrency
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @AppStorage(AppPreferences.useAllocatedBudgetForSummaryKey)
    private var useAllocatedBudgetForSummary = AppPreferences.defaultUseAllocatedBudgetForSummary
    @StateObject private var rates = ExchangeRateStore()
    @State private var month: Date
    @State private var expandedPoolIDs: Set<UUID> = []
    @State private var showsAllAttention = false

    init(initialMonth: Date = .now) {
        _month = State(initialValue: BudgetMonth.start(of: initialMonth))
    }

    var body: some View {
        AppList(usesScrollEdgeFades: false) {
            AppSection { summary }
                .modifier(FinanceSectionMargins())

            if budgetIsLoaded {
                if budgetStore.budget(accountID: accountStore.selectedAccountID) == nil {
                    AppSection {
                        NavigationLink { editor } label: {
                            Label("Set up a budget", icon: "percentage-circle")
                                .font(.headline)
                        }
                    } footer: {
                        Text("Set a monthly limit, organize categories into pools, or give a category its own limit.")
                    }
                } else if let budget = convertedBudget, let transactions = convertedExpenses {
                    limits(budget: budget, transactions: transactions)
                }
            }

            FinanceListBottomSpacer()
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(AppSpacing.large))
        .financePage()
        .navigationTitle("Budget")
        .navigationBarTitleDisplayMode(.large)
        .legacyLeadingNavigationTitle("Budget")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FinanceMonthPickerButton(month: $month)
            }
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Group {
                    if canEdit {
                        NavigationLink { editor } label: {
                            AppIcon("settings")
                        }
                        .accessibilityLabel("Budget settings")
                    }
                }
                .legacyToolbarControl()
            }
        }
        .task(id: budgetScope) { await loadBudget() }
        .task(id: rateScope) { await loadRates() }
        .onChange(of: budgetScope) { _, _ in
            expandedPoolIDs = []
            showsAllAttention = false
        }
        .task {
            await transactionStore.loadCategories()
            if transactionStore.state != .loaded, transactionStore.state != .loading {
                await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if budgetIsLoaded,
           budgetStore.budget(accountID: accountStore.selectedAccountID) == nil || convertedBudget != nil,
                  let transactions = convertedExpenses {
            let spent = transactions.reduce(Decimal.zero) { $0 + (Decimal(string: $1.amount) ?? 0) }
            let limit = convertedBudget?.summaryLimit(useAllocatedBudget: useAllocatedBudgetForSummary)
            DashboardSummaryCard(
                insights: DashboardInsights(
                    income: 0, spent: spent, previousSpent: 0, net: -spent, monthlyLimit: limit
                ),
                currency: currency,
                showsMetrics: false,
                spendingTitle: calendar.isDate(month, equalTo: .now, toGranularity: .month)
                    ? "Spent this month" : "Spent in \(month.formatted(.dateTime.month(.wide).year()))"
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            FinanceSummaryUnavailable(state: transactionStore.state, rateState: rates.state)

        }
    }

    @ViewBuilder
    private func limits(budget: MonthlyBudget, transactions: [FinanceTransaction]) -> some View {
        let overview = BudgetOverviewData(
            budget: budget, transactions: transactions, categories: transactionStore.categories
        )
        if !overview.attention.isEmpty {
            AppSection("Needs attention") {
                ForEach(showsAllAttention ? overview.attention : Array(overview.attention.prefix(2))) { item in
                    NavigationLink {
                        spendingDestination(
                            title: item.progress.name,
                            scope: item.isPool ? .pool(item.progress.id) : .category(item.progress.id)
                        )
                    } label: {
                        BudgetAttentionRow(item: item, currency: currency)
                    }
                    .accessibilityHint("View transactions")
                    .listRowBackground(AppColor.elevatedSurface.overlay(AppColor.warning.opacity(0.08)))
                }
                if overview.attention.count > 2 {
                    Button(showsAllAttention ? "Show fewer" : "Show all \(overview.attention.count) over-budget limits") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            showsAllAttention.toggle()
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }

        ForEach(Array(overview.pools.enumerated()), id: \.element.id) { index, pool in
            if index == 0 {
                poolSection(pool) {
                    Text("Pools")
                }
            } else {
                poolSection(pool) { EmptyView() }
            }
        }

        if !overview.standaloneCategories.isEmpty {
            AppSection("Categories") {
                ForEach(overview.standaloneCategories) { category in
                    categoryRow(category)
                        .listRowInsets(EdgeInsets(top: AppSpacing.compact, leading: AppSpacing.large,
                                                 bottom: AppSpacing.compact, trailing: AppSpacing.large))
                }
            }
        }
    }

    private func poolSection<Header: View>(
        _ pool: BudgetOverviewData.Pool, @ViewBuilder header: () -> Header
    ) -> some View {
        let tint = BudgetGroupPalette.color(for: pool.id)
        let expanded = expandedPoolIDs.contains(pool.id)
        return AppSection {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    if expanded { expandedPoolIDs.remove(pool.id) }
                    else { expandedPoolIDs.insert(pool.id) }
                }
            } label: {
                BudgetPoolHeader(
                    progress: pool.progress, categoryCount: pool.categories.count,
                    iconName: pool.iconName, tint: tint,
                    monthProgress: BudgetOverviewData.monthProgress(month: month, calendar: calendar),
                    isExpanded: expanded, currency: currency
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("budgetPool-\(pool.id)")
            .listRowSeparator(.hidden)

            if expanded {
                ForEach(pool.categories) { category in
                    categoryRow(category, outsidePool: pool.spendingOutsidePool[category.id])
                        .listRowInsets(EdgeInsets(top: AppSpacing.extraSmall, leading: AppSpacing.large,
                                                 bottom: AppSpacing.extraSmall, trailing: AppSpacing.large))
                        .listRowSeparator(.hidden)
                }
                if pool.categories.isEmpty {
                    Text("Assign categories in budget settings to start tracking this pool.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                NavigationLink {
                    spendingDestination(title: pool.progress.name, scope: .pool(pool.id))
                } label: {
                    HStack(spacing: AppSpacing.medium) {
                        AppIcon("list", size: 16)
                            .frame(width: 32, height: 32)
                            .accessibilityHidden(true)
                        Text("View transactions")
                            .font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .accessibilityLabel("View \(pool.progress.name) transactions")
                .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.large,
                                         bottom: AppSpacing.extraSmall, trailing: AppSpacing.large))
                .listRowSeparator(.hidden)
            }
        } header: { header() }
    }

    private func categoryRow(
        _ category: BudgetCategorySpending, outsidePool: Decimal? = nil
    ) -> some View {
        NavigationLink {
            spendingDestination(title: category.name, scope: .category(category.id))
        } label: {
            BudgetLimitRow(
                name: category.name, spent: category.spent, limit: category.limit, currency: currency,
                tint: category.category.map { AppColor.iconForeground(for: $0.displayColor) } ?? AppColor.accent,
                context: outsidePool.map {
                    "Includes \(MoneyFormatter.format($0, currency: currency, roundToWhole: roundTotals)) outside this pool"
                }
            ) {
                if let savedCategory = category.category {
                    CategoryIcon(category: savedCategory, size: 32)
                } else {
                    AppIcon("tag", size: 15)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(AppColor.controlFill, in: RoundedRectangle(cornerRadius: AppRadius.small))
                }
            }
        }
        .accessibilityHint("View category transactions")
    }

    private var editor: some View {
        BudgetSettingsView(
            accountID: accountStore.selectedAccountID,
            currency: budgetStore.budget(accountID: accountStore.selectedAccountID)?.currency ?? currency, budget: budgetStore.budget(accountID: accountStore.selectedAccountID)
        )
        .navigationTitle("Edit budget")
        .navigationBarTitleDisplayMode(.large)
    }

    private func spendingDestination(title: String, scope: BudgetTransactionsView.Scope) -> some View {
        BudgetTransactionsView(
            title: title, scope: scope, month: month,
            accountID: accountStore.selectedAccountID, currency: currency
        )
        .environmentObject(rates)
    }

    private var currency: String { accountStore.selectedAccount?.currency ?? reportingCurrency.uppercased() }
    private var expenses: [FinanceTransaction] {
        let scoped = transactionStore.allTransactions.filter {
            $0.kind == .expense && (accountStore.selectedAccountID == nil || $0.accountId == accountStore.selectedAccountID)
        }
        return FinanceOverviewData.transactions(scoped, in: month, calendar: calendar)
    }
    private var convertedExpenses: [FinanceTransaction]? {
        FinanceOverviewData.converted(expenses, to: currency, using: rates)
    }
    private var convertedBudget: MonthlyBudget? {
        guard budgetIsLoaded else { return nil }
        return budgetStore.budget(accountID: accountStore.selectedAccountID)?.converted(to: currency, using: rates)
    }
    private var budgetIsLoaded: Bool { budgetStore.isLoaded(accountID: accountStore.selectedAccountID) }
    private var canEdit: Bool { true }
    private var budgetScope: String { budgetKey(accountID: accountStore.selectedAccountID) }
    private var currencies: Set<String> {
        Set(expenses.map(\.currency) + [budgetIsLoaded ? budgetStore.budget(accountID: accountStore.selectedAccountID)?.currency : nil].compactMap { $0 })
    }
    private var rateScope: String { "\(currency):\(currencies.sorted().joined(separator: ","))" }
    private func loadBudget(force: Bool = false) async {
        await budgetStore.loadBudget(accountID: accountStore.selectedAccountID, force: force)
    }
    private func loadRates(force: Bool = false) async {
        await rates.load(currencies: currencies, reportingCurrency: currency, force: force)
    }
    private func refresh() async {
        await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        await loadBudget(force: true)
        await loadRates(force: true)
    }
}
