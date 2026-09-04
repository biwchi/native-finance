import SwiftUI

struct PlanView: View {
    private struct SummaryCardBoundsPreferenceKey: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil

        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = nextValue() ?? value
        }
    }

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

                if budgetIsLoaded, let budget = convertedBudget,
                    let transactions = monthTransactions,
                    transactionStore.state == .loaded
                {
                    let pools = BudgetLimitProgress.pools(
                        budget: budget, transactions: transactions)
                    let categories = BudgetLimitProgress.categories(
                        budget: budget, transactions: transactions,
                        categories: transactionStore.categories
                    )
                    if !pools.isEmpty { limitsSection("Budget pools", rows: pools) }
                    if !categories.isEmpty {
                        limitsSection("Category limits", rows: categories)
                    }
                }

                ComingUpSection { editingUpcomingTransaction = $0 }
                    .modifier(FinanceSectionMargins())
                FinanceListBottomSpacer()
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(4))
            .environment(\.defaultMinListRowHeight, 0)
            .financePage(detachedPreference: SummaryCardBoundsPreferenceKey.self) {
                bounds, proxy in
                if let bounds {
                    let frame = proxy[bounds]
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        if let summary = currentSummary(at: context.date) {
                            summaryButton(for: summary)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .leadingAccountSelectorToolbar()
            .financeMonthPickerToolbar(month: $selectedMonth)
            .refreshable { await reload() }
        }
        .task(id: budgetScope) {
            await budgetStore.loadBudget(
                month: selectedMonth, accountID: accountStore.selectedAccountID)
        }
        .task { await transactionStore.loadCategories() }
        .task(id: rateScope) { await loadRates() }
        .sheet(isPresented: $isShowingBudgetSettings) {
            BudgetSettingsView(
                month: selectedMonth,
                accountID: accountStore.selectedAccountID,
                currency: currency,
                budget: convertedBudget
            )
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
        if case .failed(let message) = budgetStore.state {
            VStack(alignment: .leading, spacing: 12) {
                Text("Couldn’t load budget").font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                PrimaryActionButton("Try Again", appearance: .prominent) {
                    Task {
                        await budgetStore.loadBudget(
                            month: selectedMonth,
                            accountID: accountStore.selectedAccountID,
                            force: true
                        )
                    }
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
                    let interval = Calendar.current.dateInterval(of: .month, for: selectedMonth)
                {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        if let summary = MonthlySummaryState(
                            monthlyBudget: limit, amountSpent: insights.spent,
                            currentDate: context.date,
                            startOfMonth: interval.start, endOfMonth: interval.end,
                            currency: currency, locale: locale
                        ) {
                            if #available(iOS 26.0, *) {
                                summaryButton(for: summary)
                                    .hidden()
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                    .overlay {
                                        Button {
                                            isShowingBudgetSettings = true
                                        } label: {
                                            Color.clear
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHidden(true)
                                    }
                                    .anchorPreference(
                                        key: SummaryCardBoundsPreferenceKey.self,
                                        value: .bounds
                                    ) { $0 }
                            } else {
                                summaryButton(for: summary)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    FinanceSummaryUnavailable(
                        state: transactionStore.state, rateState: summaryRates.state)
                }
            } else {
                setupBudget
            }
        } else {
            FinanceSummaryUnavailable(state: .loaded, rateState: summaryRates.state)
        }
    }

    private func summaryButton(for summary: MonthlySummaryState) -> some View {
        Button {
            isShowingBudgetSettings = true
        } label: {
            MonthlySummaryCompactView(
                state: summary, showsPlannedBills: true,
                plannedBills: forecast(for: summary),
                isLoadingPlannedBills: transactionStore.upcomingState == .loading
                    || transactionStore.upcomingState == .idle,
                surface: .glass
            )
        }
        .buttonStyle(MonthlySummaryButtonStyle())
        .accessibilityHint("Open budget settings")
    }

    private func currentSummary(at date: Date) -> MonthlySummaryState? {
        guard
            let budget = convertedBudget,
            let limit = budget.monthlyLimit.flatMap({ Decimal(string: $0) }),
            limit > 0,
            transactionStore.state == .loaded,
            let insights,
            let interval = Calendar.current.dateInterval(of: .month, for: selectedMonth)
        else {
            return nil
        }

        return MonthlySummaryState(
            monthlyBudget: limit,
            amountSpent: insights.spent,
            currentDate: date,
            startOfMonth: interval.start,
            endOfMonth: interval.end,
            currency: currency,
            locale: locale
        )
    }

    private var setupBudget: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(budgetStore.budget == nil ? "Set up your budget" : "Set a monthly limit")
                .font(.title3.weight(.semibold))
            Text("Choose a monthly spending limit to see what remains after planned bills.")
                .font(.subheadline).foregroundStyle(.secondary)
            PrimaryActionButton(
                budgetStore.budget == nil ? "Set up budget" : "Set monthly limit",
                appearance: .prominent
            ) {
                isShowingBudgetSettings = true
            }
        }
        .padding(.vertical, 12)
    }

    private func limitsSection(_ title: String, rows: [BudgetLimitProgress]) -> some View {
        Section {
            ForEach(rows) { row in
                Button {
                    isShowingBudgetSettings = true
                } label: {
                    BudgetLimitRow(progress: row, currency: currency)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit budget limits")
            }
        } header: {
            FinanceSectionHeader(title) {
                Button("Edit") { isShowingBudgetSettings = true }
            }
            .listRowInsets(
                EdgeInsets(
                    top: AppSpacing.medium,
                    leading: AppSpacing.large,
                    bottom: 0,
                    trailing: AppSpacing.large
                )
            )
        }
        .modifier(FinanceSectionMargins())
    }

    private var currency: String {
        accountStore.selectedAccount?.currency ?? reportingCurrency.uppercased()
    }
    private var budgetScope: String {
        "\(accountStore.selectedAccountID?.uuidString ?? "all"):\(BudgetMonth.key(for: selectedMonth))"
    }
    private var budgetIsLoaded: Bool {
        budgetStore.isLoaded(month: selectedMonth, accountID: accountStore.selectedAccountID)
    }
    private var convertedBudget: MonthlyBudget? {
        guard budgetIsLoaded else { return nil }
        return budgetStore.budget?.converted(to: currency, using: summaryRates)
    }
    private var convertedTransactions: [FinanceTransaction]? {
        FinanceOverviewData.converted(
            transactionStore.transactions, to: currency, using: summaryRates)
    }
    private var monthTransactions: [FinanceTransaction]? {
        convertedTransactions.map { FinanceOverviewData.transactions($0, in: selectedMonth) }
    }
    private var insights: DashboardInsights? {
        convertedTransactions.map {
            DashboardInsights.calculate(
                transactions: $0, month: selectedMonth,
                monthlyLimit: convertedBudget?.monthlyLimit.flatMap { Decimal(string: $0) })
        }
    }
    private var currencies: Set<String> {
        Set(
            transactionStore.transactions.map(\.currency)
                + transactionStore.upcomingTransactions.map(\.currency)
                + [budgetStore.budget?.currency].compactMap { $0 })
    }
    private var rateScope: String { "\(currency):\(currencies.sorted().joined(separator: ","))" }
    private func forecast(for summary: MonthlySummaryState) -> PlannedBillsSummary? {
        guard transactionStore.upcomingState == .loaded else { return nil }
        return PlannedBillsSummary.calculate(
            summary: summary, transactions: transactionStore.transactions,
            upcoming: transactionStore.upcomingTransactions
        ) { amount, sourceCurrency in
            summaryRates.convert(amount, from: sourceCurrency, to: currency)
        }
    }
    private func loadRates(force: Bool = false) async {
        await summaryRates.load(currencies: currencies, reportingCurrency: currency, force: force)
    }
    private func reload() async {
        async let transactions: Void = transactionStore.loadTransactions(
            accountID: accountStore.selectedAccountID)
        async let budget: Void = budgetStore.loadBudget(
            month: selectedMonth,
            accountID: accountStore.selectedAccountID,
            force: true
        )
        _ = await (transactions, budget)
        await loadRates(force: true)
    }
}
