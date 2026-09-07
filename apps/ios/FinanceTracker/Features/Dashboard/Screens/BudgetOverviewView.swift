import SwiftUI

struct BudgetOverviewView: View {
    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @AppStorage(AppPreferences.defaultCurrencyKey) private var reportingCurrency = AppPreferences.initialCurrency
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @StateObject private var rates = ExchangeRateStore()
    @State private var month: Date

    init(initialMonth: Date = .now) {
        _month = State(initialValue: BudgetMonth.start(of: initialMonth))
    }

    var body: some View {
        List {
            Section { summary }
                .modifier(FinanceSectionMargins())

            if budgetIsLoaded {
                if budgetStore.budget == nil {
                    Section {
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
        .financePage(usesNativeNavigationTitle: true)
        .navigationTitle("Budget")
        .navigationBarTitleDisplayMode(.large)
        .financeMonthPickerToolbar(month: $month)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if canEdit {
                    NavigationLink { editor } label: {
                        AppIcon("settings")
                    }
                    .accessibilityLabel("Budget settings")
                }
            }
        }
        .task(id: budgetScope) { await loadBudget() }
        .task(id: rateScope) { await loadRates() }
        .task {
            await transactionStore.loadCategories()
            if transactionStore.state != .loaded, transactionStore.state != .loading {
                await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
            }
        }
        .refreshable { await refresh() }
    }

    @ViewBuilder
    private var summary: some View {
        if case .failed(let message) = budgetStore.state {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Couldn’t load budget").font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                Button("Try Again") { Task { await loadBudget(force: true) } }
            }
        } else if !budgetIsLoaded {
            ProgressView("Loading budget").frame(maxWidth: .infinity).padding(.vertical, AppSpacing.large)
                .listRowBackground(Color.clear)
        } else if transactionStore.state == .loaded,
                  budgetStore.budget == nil || convertedBudget != nil,
                  let transactions = convertedExpenses {
            let spent = transactions.reduce(Decimal.zero) { $0 + (Decimal(string: $1.amount) ?? 0) }
            let limit = convertedBudget?.monthlyLimit.flatMap { Decimal(string: $0) }
            let remaining = limit.map { $0 - spent }
            FinanceHighlightCard(
                title: remaining.map { $0 < 0 ? "Over budget" : "Budget left" } ?? "Spent this month",
                amount: abs(remaining ?? spent), currency: currency,
                detail: "\(month.formatted(.dateTime.month(.wide).year())) · \(accountStore.selectedAccount?.name ?? "All accounts")",
                amountColor: (remaining ?? 0) < 0 ? AppColor.destructiveText : .primary
            ) {
                if let limit, limit > 0 {
                    BudgetProgressBar(
                        budgetProgress: NSDecimalNumber(decimal: spent / limit).doubleValue,
                        monthProgress: nil,
                        tint: spent > limit ? AppColor.destructiveText : AppColor.accent
                    )
                    MonthlySummaryRow {
                        Text("\(money(spent)) spent")
                    } trailing: {
                        Text("of \(money(limit))")
                    }
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text("No overall monthly limit set.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } else {
            FinanceSummaryUnavailable(state: transactionStore.state, rateState: rates.state)
            if case .failed = rates.state {
                Button("Retry exchange rates") { Task { await loadRates(force: true) } }
            }
        }
    }

    @ViewBuilder
    private func limits(budget: MonthlyBudget, transactions: [FinanceTransaction]) -> some View {
        let pools = BudgetLimitProgress.pools(budget: budget, transactions: transactions)
        let categories = BudgetCategorySpending.calculate(
            budget: budget, transactions: transactions, categories: transactionStore.categories
        )
        if !pools.isEmpty {
            Section {
                ForEach(pools) { progress in
                    NavigationLink {
                        spendingDestination(title: progress.name, scope: .pool(progress.id))
                    } label: {
                        BudgetLimitRow(progress: progress, currency: currency)
                    }
                }
            } header: {
                Text("Budget pools")
            } footer: {
                Text("Tap a pool to see the transactions using its budget.")
            }
        }
        if !categories.isEmpty {
            Section("Categories") {
                ForEach(categories) { category in
                    NavigationLink {
                        spendingDestination(title: category.name, scope: .category(category.id))
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                            if let progress = category.progress {
                                BudgetLimitRow(progress: progress, currency: currency)
                            } else {
                                MonthlySummaryRow {
                                    Text(category.name).font(.body.weight(.medium))
                                } trailing: {
                                    Text("\(money(category.spent)) spent").font(.subheadline).monospacedDigit()
                                }
                                .padding(.vertical, AppSpacing.compact)
                            }
                            Text(category.poolName.map { "Pool: \($0)" } ?? "Independent category limit")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, AppSpacing.extraSmall)
                    }
                }
            }
        }
    }

    private var editor: some View {
        BudgetSettingsView(
            month: month, accountID: accountStore.selectedAccountID,
            currency: currency, budget: convertedBudget
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
        return budgetStore.budget?.converted(to: currency, using: rates)
    }
    private var budgetIsLoaded: Bool { budgetStore.isLoaded(month: month, accountID: accountStore.selectedAccountID) }
    private var canEdit: Bool { budgetIsLoaded && (budgetStore.budget == nil || convertedBudget != nil) }
    private var budgetScope: String { "\(accountStore.selectedAccountID?.uuidString ?? "all"):\(BudgetMonth.key(for: month))" }
    private var currencies: Set<String> {
        Set(expenses.map(\.currency) + [budgetIsLoaded ? budgetStore.budget?.currency : nil].compactMap { $0 })
    }
    private var rateScope: String { "\(currency):\(currencies.sorted().joined(separator: ","))" }
    private func money(_ value: Decimal) -> String {
        MoneyFormatter.format(value, currency: currency, roundToWhole: roundTotals)
    }
    private func loadBudget(force: Bool = false) async {
        await budgetStore.loadBudget(month: month, accountID: accountStore.selectedAccountID, force: force)
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
