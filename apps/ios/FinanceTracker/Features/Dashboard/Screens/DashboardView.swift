import SwiftUI

struct DashboardView: View {
    var isPresentingQuickEntry = false
    var onAddTransaction: () -> Void = {}

    private enum SummaryCardID: Hashable {
        case summary
    }

    private struct TransactionResultsScope: Equatable {
        let period: FinanceDateFilter
        let accountID: UUID?
        let isLoaded: Bool
    }

    private struct AnimatedSummaryHeight<Content: View>: View, Animatable {
        var height: CGFloat
        @ViewBuilder var content: (CGFloat?) -> Content

        var animatableData: CGFloat {
            get { height }
            set { height = newValue }
        }

        var body: some View {
            content(height > 0 ? height : nil)
        }
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

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var budgetStore: BudgetStore
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @StateObject private var summaryRates = ExchangeRateStore()
    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var reportingCurrency = AppPreferences.initialCurrency
    @AppStorage(AppPreferences.recurringReminderDaysKey)
    private var recurringReminderDays = AppPreferences.defaultRecurringReminderDays
    @State private var selectedPeriod = FinanceDateFilter()
    @State private var isShowingRecurring = false
    @State private var isShowingBudget = false
    @State private var selectedSummaryMetric: DashboardSummaryMetrics.Metric?
    @State private var editingTransaction: FinanceTransaction?
    @State private var deletingTransactionID: UUID?
    @State private var deletionError: String?
    @State private var summaryCardHeight: CGFloat?
    @State private var animatesSummaryHeight = false

    var body: some View {
        NavigationStack {
            dashboardContent
                .navigationDestination(isPresented: $isShowingRecurring) {
                    RecurringTransactionsView()
                }
                .navigationDestination(isPresented: $isShowingBudget) {
                    BudgetOverviewView(initialMonth: selectedPeriod.anchor)
                }
                .task(id: budgetScope) {
                    if selectedPeriod.preset == .month {
                        await budgetStore.loadBudget(month: selectedPeriod.anchor, accountID: accountStore.selectedAccountID)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isPresentingQuickEntry {
                        addTransactionButton
                    }
                }
                .financeOverviewToolbar()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 0) {
                            NavigationLink {
                                FinancesView(initialMonth: selectedPeriod.preset == .month ? selectedPeriod.anchor : .now)
                            } label: {
                                AppIcon("view-grid")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Finances")
                            .accessibilityIdentifier("financesNavigation")

                            NavigationLink {
                                SettingsView()
                            } label: {
                                AppIcon("settings")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Settings")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .refreshable { await reload() }
        }
        .task(id: rateScope) { await loadRates() }
        .sheet(item: $selectedSummaryMetric) { metric in
            if let insights {
                DashboardSummaryMetrics.Detail(metric: metric, amount: metric.amount(in: insights), currency: currency)
            }
        }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(transaction: transaction)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Couldn't delete transaction", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionError ?? "")
        }
    }

    private var addTransactionButton: some View {
        PrimaryIconButton(
            "Add transaction",
            iconName: "plus",
            iconSize: 26,
            appearance: .glass,
            action: onAddTransaction
        )
        .dynamicTypeSize(.large)
        .frame(width: 62, height: 62)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.small)
        .background {
            bottomScrollFade
        }
    }

    @ViewBuilder
    private var bottomScrollFade: some View {
        if #available(iOS 26.0, *) {
            GeometryReader { proxy in
                FinanceToolbarBlurView(transitionHeight: 64, edge: .bottom)
                    .overlay {
                        AppColor.groupedBackground
                            .mask {
                                LinearGradient(stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black.opacity(0.03), location: 0.15),
                                    .init(color: .black.opacity(0.12), location: 0.3),
                                    .init(color: .black.opacity(0.38), location: 0.5),
                                    .init(color: .black.opacity(0.85), location: 1)
                                ], startPoint: .top, endPoint: .bottom)
                            }
                    }
                    .frame(height: (proxy.size.height + 40) * 2 / 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            // Drive the row and detached glass with the same displayed height on every
            // frame. Native List resize animations can crossfade self-sizing cells.
            AnimatedSummaryHeight(height: summaryCardHeight ?? 0) { height in
                KeyframeAnimator(initialValue: 1.0, trigger: transactionResultsScope) { opacity in
                    dashboardList(now: context.date, transactionOpacity: opacity,
                                  summaryHeight: height)
                } keyframes: { _ in
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: 0.2)
                }
            }
            .animation(animatesSummaryHeight && !reduceMotion ? .easeInOut(duration: 0.3) : nil,
                       value: summaryCardHeight)
        }
    }

    private var transactionResultsScope: TransactionResultsScope {
        TransactionResultsScope(period: selectedPeriod, accountID: accountStore.selectedAccountID,
                                isLoaded: transactionStore.state == .loaded)
    }

    private func dashboardList(now: Date, transactionOpacity: Double, summaryHeight: CGFloat?) -> some View {
        let reminders = FinanceOverviewData.upcomingReminders(
            transactionStore.upcomingTransactions, daysBefore: recurringReminderDays,
            now: now, calendar: calendar
        )
        return List {
            Section {
                FinancePageHeader(dateSelection: $selectedPeriod)
                if transactionStore.state == .loaded, let insights {
                    summaryCards(for: insights, height: summaryHeight)
                } else {
                    FinanceSummaryUnavailable(state: transactionStore.state, rateState: summaryRates.state)
                }
            }
            .modifier(FinanceSectionMargins())
            if transactionStore.upcomingState == .loaded, let nearest = reminders.first {
                Section {
                    Button {
                        isShowingRecurring = true
                    } label: {
                        DashboardUpcomingReminder(transaction: nearest, count: reminders.count, now: now)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Show recurring transactions")
                    .accessibilityIdentifier("recurringReminderNavigation")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .modifier(FinanceSectionMargins(top: AppSpacing.large))
            }
            transactionSections(opacity: transactionOpacity)
                // Filtering replaces the results without animating individual row moves.
                .transaction { $0.animation = nil }
            // Clear the floating Add button and its padding, then leave a 24-point gap.
            FinanceListBottomSpacer(height: 62 + AppSpacing.small * 2 + AppSpacing.doubleExtraLarge)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(AppSpacing.large))
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.defaultMinListHeaderHeight, 0)
        .financePage(detachedPreference: SummaryCardBoundsPreferenceKey.self) {
            bounds, proxy in
            if transactionStore.state == .loaded, let insights {
                ZStack {
                    summaryCardOverlay(for: insights, bounds: bounds, proxy: proxy)
                }
            }
        }
        .transaction { $0.animation = nil }
    }

    private var currency: String { accountStore.selectedAccount?.currency ?? reportingCurrency.uppercased() }
    private var currencies: Set<String> { Set(transactionStore.transactions.map(\.currency) + [budgetStore.budget?.currency].compactMap { $0 }) }
    private var rateScope: String { "\(currency):\(currencies.sorted().joined(separator: ","))" }
    private var periodTransactions: [FinanceTransaction] {
        FinanceOverviewData.transactions(transactionStore.transactions, in: selectedPeriod, calendar: calendar)
    }
    private var insights: DashboardInsights? {
        guard let converted = FinanceOverviewData.converted(transactionStore.transactions, to: currency, using: summaryRates) else { return nil }
        return DashboardInsights.calculate(transactions: converted, filter: selectedPeriod, calendar: calendar,
                                           monthlyLimit: convertedBudget?.monthlyLimit.flatMap { Decimal(string: $0) })
    }
    private var budgetScope: String {
        "\(selectedPeriod.preset.rawValue):\(accountStore.selectedAccountID?.uuidString ?? "all"):\(BudgetMonth.key(for: selectedPeriod.anchor))"
    }
    private var convertedBudget: MonthlyBudget? {
        guard selectedPeriod.preset == .month,
              budgetStore.isLoaded(month: selectedPeriod.anchor, accountID: accountStore.selectedAccountID) else { return nil }
        return budgetStore.budget?.converted(to: currency, using: summaryRates)
    }
    private var dashboardEmptyState: some View {
        ContentUnavailableView(
            "No activity yet",
            iconName: "calendar-minus",
            description: Text("No transactions in this period. Choose another period or tap + to add one.")
        )
    }

    @ViewBuilder
    private func summaryCards(for insights: DashboardInsights, height: CGFloat?) -> some View {
        summaryCardPlaceholder(.summary, height: height) {
            summaryCard(for: insights)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func summaryCardPlaceholder<Content: View>(
        _ id: SummaryCardID,
        height: CGFloat?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content()
                    .transaction { $0.disablesAnimations = true }
                    .hidden()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                content()
            }
        }
        // Measure the natural content before constraining the row. The new budget
        // height can arrive after the mode-change transaction has already finished.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            guard height > 0, height.isFinite, summaryCardHeight != height else { return }
            withTransaction(Transaction(animation: nil)) {
                animatesSummaryHeight = summaryCardHeight != nil
                summaryCardHeight = height
            }
        }
        .frame(height: height, alignment: .top)
        .clipped()
        // Both the detached card and the following sections use this animated frame.
        .anchorPreference(key: SummaryCardBoundsPreferenceKey.self, value: .bounds) { [id: $0] }
    }

    @ViewBuilder
    private func summaryCardOverlay(
        for insights: DashboardInsights,
        bounds: [SummaryCardID: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> some View {
        positionedSummaryCard(.summary, bounds: bounds, proxy: proxy) { height in
            summaryCard(for: insights, height: height)
        }
    }

    @ViewBuilder
    private func positionedSummaryCard<Content: View>(
        _ id: SummaryCardID,
        bounds: [SummaryCardID: Anchor<CGRect>],
        proxy: GeometryProxy,
        @ViewBuilder content: (CGFloat) -> Content
    ) -> some View {
        if let anchor = bounds[id] {
            let frame = proxy[anchor]
            content(frame.height)
                .frame(width: frame.width, height: frame.height, alignment: .top)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private func summaryCard(for insights: DashboardInsights, height: CGFloat? = nil) -> some View {
        DashboardSummaryCard(
            insights: insights,
            currency: currency,
            budgetTimeRemaining: budgetTimeRemaining(for: insights),
            comparisonDescription: comparisonDescription,
            onViewBudget: { isShowingBudget = true },
            onViewMetric: { selectedSummaryMetric = $0 },
            presentationHeight: height
        )
    }

    private var comparisonDescription: String {
        guard let interval = selectedPeriod.comparisonInterval(calendar: calendar),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return "" }
        let previous = FinanceDateFilter(preset: .custom, anchor: interval.start, customEnd: last)
        return "Compared with \(previous.label(calendar: calendar, locale: locale))"
    }

    private func budgetTimeRemaining(for insights: DashboardInsights) -> String? {
        guard insights.hasBudget, let interval = selectedPeriod.interval(calendar: calendar) else { return nil }
        return MonthlySummaryState(
            monthlyBudget: insights.monthlyLimit, amountSpent: insights.spent, currentDate: .now,
            startOfMonth: interval.start, endOfMonth: interval.end,
            currency: currency, locale: locale, calendar: calendar
        )?.timeRemainingText
    }

    private func loadRates(force: Bool = false) async {
        await summaryRates.load(currencies: currencies, reportingCurrency: currency, force: force)
    }
    private func reload() async {
        await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        if selectedPeriod.preset == .month {
            await budgetStore.loadBudget(month: selectedPeriod.anchor, accountID: accountStore.selectedAccountID, force: true)
        }
        await loadRates(force: true)
    }

    private var transactionGroups: [(day: Date, transactions: [FinanceTransaction])] {
        let groups = Dictionary(grouping: periodTransactions) {
            calendar.startOfDay(for: $0.occurredAt)
        }
        return groups.keys.sorted(by: >).map { (day: $0, transactions: groups[$0] ?? []) }
    }

    @ViewBuilder
    private func transactionSections(opacity: Double) -> some View {
        switch transactionStore.state {
        case .idle, .loading:
            Section {
                ProgressView("Loading transactions")
                    .frame(maxWidth: .infinity)
            }
            .modifier(FinanceSectionMargins(top: AppSpacing.large))
        case .loaded:
            if periodTransactions.isEmpty {
                Section {
                    dashboardEmptyState
                        .opacity(opacity)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                .modifier(FinanceSectionMargins(top: AppSpacing.large))
            } else {
                ForEach(transactionGroups, id: \.day) { group in
                    Section {
                        ForEach(group.transactions) { transaction in
                            transactionButton(transaction)
                                .opacity(opacity)
                        }
                    } header: {
                        Text(group.day, format: .dateTime.month(.wide).day().year())
                            .opacity(opacity)
                            .listRowInsets(EdgeInsets(
                                top: 0,
                                leading: AppSpacing.large,
                                bottom: AppSpacing.small,
                                trailing: AppSpacing.large
                            ))
                    }
                    .modifier(FinanceSectionMargins(top: AppSpacing.large))
                }
            }
        case .failed:
            Section {
                Label("Couldn’t load transactions", icon: "wifi-warning")
                    .foregroundStyle(.secondary)
            }
            .modifier(FinanceSectionMargins(top: AppSpacing.large))
        }
    }

    private func transactionButton(_ transaction: FinanceTransaction) -> some View {
        Button {
            editingTransaction = transaction
        } label: {
            TransactionRow(
                transaction: transaction,
                account: accountStore.accounts.first { $0.id == transaction.accountId },
                timestampStyle: .time
            )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit transaction")
        .disabled(deletingTransactionID != nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await delete(transaction) }
            } label: {
                Label("Delete", icon: "trash")
            }
            .disabled(deletingTransactionID != nil)
        }
    }

    private func delete(_ transaction: FinanceTransaction) async {
        guard deletingTransactionID == nil else { return }
        deletingTransactionID = transaction.id
        defer { deletingTransactionID = nil }

        do {
            try await transactionStore.deleteTransaction(transaction)
        } catch {
            deletionError = error.localizedDescription
        }
    }

}
