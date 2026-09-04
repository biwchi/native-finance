import SwiftUI

struct DashboardView: View {
    private enum SummaryCardID: Hashable {
        case prominent
        case metrics
    }

    private struct SummaryCardBoundsPreferenceKey: PreferenceKey {
        static let defaultValue: [SummaryCardID: Anchor<CGRect>] = [:]

        static func reduce(
            value: inout [SummaryCardID: Anchor<CGRect>],
            nextValue: () -> [SummaryCardID: Anchor<CGRect>]
        ) {
            value.merge(nextValue()) { _, next in next }
        }
    }

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @StateObject private var summaryRates = ExchangeRateStore()
    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var reportingCurrency = AppPreferences.initialCurrency
    @State private var selectedMonth = BudgetMonth.start(of: .now)
    @State private var editingTransaction: FinanceTransaction?
    @State private var editingUpcomingTransaction: UpcomingTransaction?
    @State private var transactionSearchText = ""

    var body: some View {
        NavigationStack {
            dashboardContent
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

    @ViewBuilder
    private var dashboardContent: some View {
        if showsEmptyDashboard {
            dashboardEmptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .financePage()
        } else {
            List {
                Section {
                    FinancePageHeader(title: "Overview")
                    if transactionStore.state == .loaded, let insights {
                        summaryCards(for: insights)
                    } else {
                        FinanceSummaryUnavailable(state: transactionStore.state, rateState: summaryRates.state)
                    }
                }
                .modifier(FinanceSectionMargins())
                recentTransactionsSection.modifier(FinanceSectionMargins())
                ComingUpSection { editingUpcomingTransaction = $0 }
                    .modifier(FinanceSectionMargins())
                FinanceListBottomSpacer()
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(4))
            .environment(\.defaultMinListRowHeight, 0)
            .financePage(detachedPreference: SummaryCardBoundsPreferenceKey.self) {
                bounds, proxy in
                if transactionStore.state == .loaded, let insights {
                    ZStack {
                        summaryCardOverlay(for: insights, bounds: bounds, proxy: proxy)
                    }
                    .allowsHitTesting(false)
                }
            }
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
    private var showsEmptyDashboard: Bool {
        transactionStore.state == .loaded
            && transactionStore.upcomingState == .loaded
            && monthTransactions.isEmpty
            && transactionStore.upcomingTransactions.isEmpty
    }
    private var dashboardEmptyState: some View {
        ContentUnavailableView(
            "No activity yet",
            iconName: "calendar-minus",
            description: Text("Tap + below to add a transaction for this month.")
        )
    }

    @ViewBuilder
    private func summaryCards(for insights: DashboardInsights) -> some View {
        switch DashboardSummaryLayout(insights: insights) {
        case .empty:
            EmptyView()
        case .spentOnly:
            summaryCardPlaceholder(.prominent) {
                prominentSummaryCard(title: "Total spent", amount: insights.spent)
            }
        case .incomeOnly:
            summaryCardPlaceholder(.prominent) {
                prominentSummaryCard(title: "Income", amount: insights.income)
            }
        case let .spentAndIncome(showsNet):
            summaryCardPlaceholder(.prominent) {
                prominentSummaryCard(title: "Total spent", amount: insights.spent)
            }
            summaryCardPlaceholder(.metrics) {
                metricSummaryCards(for: insights, showsNet: showsNet)
            }
        }
    }

    @ViewBuilder
    private func summaryCardPlaceholder<Content: View>(
        _ id: SummaryCardID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, *) {
            content()
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .anchorPreference(
                    key: SummaryCardBoundsPreferenceKey.self,
                    value: .bounds
                ) { [id: $0] }
        } else {
            content()
        }
    }

    @ViewBuilder
    private func summaryCardOverlay(
        for insights: DashboardInsights,
        bounds: [SummaryCardID: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> some View {
        switch DashboardSummaryLayout(insights: insights) {
        case .empty:
            EmptyView()
        case .spentOnly:
            positionedSummaryCard(.prominent, bounds: bounds, proxy: proxy) {
                prominentSummaryCard(title: "Total spent", amount: insights.spent)
            }
        case .incomeOnly:
            positionedSummaryCard(.prominent, bounds: bounds, proxy: proxy) {
                prominentSummaryCard(title: "Income", amount: insights.income)
            }
        case let .spentAndIncome(showsNet):
            positionedSummaryCard(.prominent, bounds: bounds, proxy: proxy) {
                prominentSummaryCard(title: "Total spent", amount: insights.spent)
            }
            positionedSummaryCard(.metrics, bounds: bounds, proxy: proxy) {
                metricSummaryCards(for: insights, showsNet: showsNet)
            }
        }
    }

    @ViewBuilder
    private func positionedSummaryCard<Content: View>(
        _ id: SummaryCardID,
        bounds: [SummaryCardID: Anchor<CGRect>],
        proxy: GeometryProxy,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let anchor = bounds[id] {
            let frame = proxy[anchor]
            content()
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private func metricSummaryCards(
        for insights: DashboardInsights,
        showsNet: Bool
    ) -> some View {
        FinanceMetricCards(
            first: .init(title: "Income", amount: insights.income),
            second: showsNet
                ? .init(
                    title: "Net",
                    amount: insights.net,
                    signed: true,
                    amountColor: AppColor.positive
                )
                : nil,
            currency: currency,
            surface: .glass
        )
    }

    private func prominentSummaryCard(title: String, amount: Decimal) -> some View {
        MonthlySummaryCard(
            monthTitle: title,
            titleColor: AppColor.accent,
            surface: .glass,
            gradientTint: AppColor.accent
        ) {} content: {
            MonthlySummaryAmount(amount: MoneyFormatter.format(amount, currency: currency))
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
                    dashboardEmptyState
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(monthTransactions.prefix(4)) { transaction in
                        Button {
                            editingTransaction = transaction
                        } label: {
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
            case .failed:
                Label("Couldn’t load transactions", icon: "wifi-warning")
                    .foregroundStyle(.secondary)
            }
        } header: {
            if transactionStore.state != .loaded || !monthTransactions.isEmpty {
                FinanceSectionHeader("Recent activity") {
                    NavigationLink {
                        TransactionListView(
                            showsOverview: true,
                            month: selectedMonth,
                            searchText: $transactionSearchText
                        )
                    } label: {
                        Text("See all")
                    }
                    .accessibilityLabel("See all transactions")
                }
                .listRowInsets(EdgeInsets(top: AppSpacing.medium, leading: AppSpacing.large, bottom: 0, trailing: AppSpacing.large))
            }
        }
    }

}

enum DashboardSummaryLayout: Equatable {
    case empty
    case spentOnly
    case incomeOnly
    case spentAndIncome(showsNet: Bool)

    init(insights: DashboardInsights) {
        switch (insights.spent != .zero, insights.income != .zero) {
        case (false, false):
            self = .empty
        case (true, false):
            self = .spentOnly
        case (false, true):
            self = .incomeOnly
        case (true, true):
            self = .spentAndIncome(showsNet: insights.net != .zero)
        }
    }
}
