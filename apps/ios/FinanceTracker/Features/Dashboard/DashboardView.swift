import SwiftUI

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @EnvironmentObject private var exchangeRateStore: ExchangeRateStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var reportingCurrency = AppPreferences.initialCurrency

    @State private var selectedMonth = BudgetMonth.start(of: .now)
    @State private var isShowingBudgetSettings = false
    @State private var isShowingMonthPicker = false
    @State private var editingTransaction: FinanceTransaction?
    @State private var editingUpcomingTransaction: UpcomingTransaction?

    var body: some View {
        NavigationStack {
            List {
                monthlyBudgetProgressSection
                    .modifier(DashboardSectionMargins())

                monthlyHighlightsSection
                    .modifier(DashboardSectionMargins())

                recentTransactionsSection
                    .modifier(DashboardSectionMargins())

                if transactionStore.upcomingState == .loaded,
                   !transactionStore.upcomingTransactions.isEmpty {
                    upcomingTransactionsSection
                        .modifier(DashboardSectionMargins())
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(4))
            .scrollContentBackground(.hidden)
            .backgroundPreferenceValue(DashboardSummaryBoundsKey.self) { anchors in
                monthlySummaryBackground(anchors)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .environment(\.defaultMinListRowHeight, 0)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        AccountSelector(compact: true)
                            // Compensate for the inset retained by the hidden system glass.
                            .padding(.leading, -12)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        AccountSelector(compact: true)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        if isAllAccounts {
                            budgetSettingsButton
                        }

                        Button {
                            isShowingMonthPicker = true
                        } label: {
                            AppIcon("calendar")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Choose month")
                        .accessibilityValue(monthTitle)
                        .popover(isPresented: $isShowingMonthPicker) {
                            DashboardMonthPicker(
                                selection: $selectedMonth,
                                range: earliestMonth...latestMonth
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .refreshable { await reload() }
        }
        .task(id: budgetScopeKey) {
            await loadBudget()
        }
        .task(id: exchangeRateScopeKey) {
            await exchangeRateStore.load(
                currencies: exchangeCurrencies,
                reportingCurrency: dashboardCurrency
            )
        }
        .sheet(isPresented: $isShowingBudgetSettings) {
            BudgetSettingsView(
                month: selectedMonth,
                accountID: accountStore.selectedAccountID,
                currency: dashboardCurrency,
                budget: convertedBudget
            )
            .environmentObject(budgetStore)
            .environmentObject(transactionStore)
            .environmentObject(exchangeRateStore)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(transaction: transaction)
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingUpcomingTransaction) { transaction in
            AddTransactionView(upcomingTransaction: transaction)
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var budgetSettingsButton: some View {
        Button {
            isShowingBudgetSettings = true
        } label: {
            AppIcon("percentage-circle")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!canOpenBudget)
        .accessibilityLabel("Budget settings")
    }

    @ViewBuilder
    private var dashboardHighlight: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                switch transactionStore.state {
                case .idle, .loading:
                    ProgressView("Loading monthly spending")
                        .frame(maxWidth: .infinity, alignment: .center)
                case let .failed(message):
                    Label(message, icon: "warning-triangle")
                        .foregroundStyle(.secondary)
                case .loaded:
                    if budgetStore.state == .loading {
                        ProgressView("Loading monthly spending")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let insights {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(highlightText(for: insights))
                                .font(.title.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .contentTransition(.numericText())

                            if let monthlyLimit = insights.monthlyLimit {
                                Text(
                                    "of \(money(monthlyLimit, currency: dashboardCurrency)) monthly budget"
                                )
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            }
                        }
                    } else {
                        switch exchangeRateStore.state {
                        case .idle, .loading:
                            ProgressView("Converting to \(dashboardCurrency)")
                        case let .failed(message):
                            Label(message, icon: "refresh-double")
                                .foregroundStyle(.secondary)
                        case .loaded:
                            Label(
                                "Some currencies could not be converted", icon: "warning-triangle"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func highlightText(for insights: DashboardInsights) -> String {
        if let remaining = insights.remaining, remaining >= 0 {
            return "\(money(remaining, currency: dashboardCurrency)) left to spend"
        }
        return "\(money(insights.spent, currency: dashboardCurrency)) spent \(monthTitle)"
    }

    private func money(_ value: Decimal, currency: String, spoken: Bool = false) -> String {
        spoken
            ? MoneyFormatter.spoken(value, currency: currency, locale: locale)
            : MoneyFormatter.format(value, currency: currency)
    }

    @ViewBuilder
    private var monthlyBudgetProgressSection: some View {
        if transactionStore.state == .loaded,
           !isAllAccounts || budgetStore.state == .loaded,
           let insights,
           !isAllAccounts || budgetStore.budget == nil || convertedBudget != nil,
           let interval = Calendar.current.dateInterval(of: .month, for: selectedMonth) {
            Section {
                Group {
                    if let monthlyLimit = insights.monthlyLimit,
                       !monthlyLimit.isNaN, monthlyLimit > 0 {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            if let summary = MonthlySummaryState(
                                monthlyBudget: monthlyLimit,
                                amountSpent: insights.spent,
                                currentDate: context.date,
                                startOfMonth: interval.start,
                                endOfMonth: interval.end,
                                currency: dashboardCurrency,
                                locale: locale
                            ) {
                                Button {
                                    isShowingBudgetSettings = true
                                } label: {
                                    MonthlySummaryCompactView(state: summary)
                                }
                                .buttonStyle(MonthlySummaryButtonStyle())
                                .accessibilityHint("Open budget settings")
                            }
                        }
                    } else {
                        MonthlyActivitySummaryView(
                            insights: insights,
                            monthTitle: monthTitle,
                            isCurrentMonth: Calendar.current.isDate(
                                selectedMonth, equalTo: .now, toGranularity: .month
                            ),
                            currency: dashboardCurrency,
                            showsBudgetSettings: isAllAccounts,
                            canSetBudget: canOpenBudget
                        ) {
                            isShowingBudgetSettings = true
                        }
                    }
                }
                .environment(\.monthlySummaryCardBackground, .clear)
                .anchorPreference(key: DashboardSummaryBoundsKey.self, value: .bounds) {
                    [.summary: $0]
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var monthlyHighlightsSection: some View {
        if transactionStore.state == .loaded,
           let insights {
            let hasMonthlyBudget = insights.monthlyLimit.map { !$0.isNaN && $0 > 0 } ?? false
            // The activity card already shows total spending when there is no income.
            if insights.income > 0 || (insights.spent > 0 && hasMonthlyBudget) {
                monthlyHighlights(for: insights)
            }
        }
    }

    private func monthlyHighlights(for insights: DashboardInsights) -> some View {
        Section {
            HStack(spacing: 0) {
                if insights.income > 0 {
                    monthlyHighlight(
                        title: "Income",
                        amount: insights.income,
                        iconName: "arrow-down-left",
                        color: .green,
                        amountColor: .green
                    )
                }

                if insights.spent > 0 {
                    if insights.income > 0 {
                        Spacer(minLength: 16)
                    }

                    monthlyHighlight(
                        title: "Spent",
                        amount: insights.spent,
                        iconName: "arrow-up-right",
                        color: .orange,
                        amountColor: .primary
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
            .anchorPreference(key: DashboardSummaryBoundsKey.self, value: .bounds) {
                [.highlights: $0]
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func monthlySummaryBackground(
        _ anchors: [DashboardSummaryRegion: Anchor<CGRect>]
    ) -> some View {
        GeometryReader { geometry in
            if let summary = anchors[.summary] {
                let summaryFrame = geometry[summary]
                let highlightsFrame = anchors[.highlights].map { geometry[$0] }
                let bounds = highlightsFrame.map { summaryFrame.union($0) } ?? summaryFrame

                // Join the existing sections visually without changing their layout or hit targets.
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color(red: 43 / 255, green: 33 / 255, blue: 20 / 255)
                          : Color(red: 1, green: 240 / 255, blue: 215 / 255))
                    .frame(width: bounds.width, height: bounds.height)
                    .position(x: bounds.midX, y: bounds.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func monthlyHighlight(
        title: String,
        amount: Decimal,
        iconName: String,
        color: Color,
        amountColor: Color
    ) -> some View {
        HStack(spacing: 6) {
            AppIcon(iconName, size: 9)
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
                .background(color.opacity(0.2), in: Circle())

            Text(money(amount, currency: dashboardCurrency))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(amountColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(money(amount, currency: dashboardCurrency, spoken: true))
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
                Text("Latest transactions")

                Spacer()

                NavigationLink {
                    TransactionsView()
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

    private var upcomingTransactionsSection: some View {
        Section {
            UpcomingTransactionsContent(limit: 4, onEdit: { editingUpcomingTransaction = $0 })
        } header: {
            HStack {
                Text("Coming up")

                Spacer()

                NavigationLink {
                    RecurringTransactionsView()
                } label: {
                    Text("See all")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
                .accessibilityLabel("See all recurring transactions")
            }
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
        }
    }

    private var insights: DashboardInsights? {
        guard let transactions = convertedTransactions else { return nil }
        return DashboardInsights.calculate(
            transactions: transactions,
            month: selectedMonth,
            monthlyLimit: convertedBudget?.monthlyLimit.flatMap { Decimal(string: $0) }
        )
    }

    private var dashboardCurrency: String {
        if let account = accountStore.selectedAccount {
            return account.currency
        }
        return reportingCurrency.uppercased()
    }

    private var convertedTransactions: [FinanceTransaction]? {
        var converted: [FinanceTransaction] = []
        converted.reserveCapacity(transactionStore.transactions.count)
        for transaction in transactionStore.transactions {
            guard let amount = Decimal(
                string: transaction.amount,
                locale: Locale(identifier: "en_US_POSIX")
            ), let convertedAmount = exchangeRateStore.convert(
                amount,
                from: transaction.currency,
                to: dashboardCurrency
            ) else {
                return nil
            }
            converted.append(
                transaction.replacingAmount(
                    NSDecimalNumber(decimal: convertedAmount).stringValue,
                    currency: dashboardCurrency
                )
            )
        }
        return converted
    }

    private var convertedBudget: MonthlyBudget? {
        guard isAllAccounts, let budget = budgetStore.budget else { return nil }
        return budget.converted(to: dashboardCurrency, using: exchangeRateStore)
    }

    private var exchangeCurrencies: Set<String> {
        let accountCurrencies: [String]
        if let selectedAccount = accountStore.selectedAccount {
            accountCurrencies = [selectedAccount.currency]
        } else {
            accountCurrencies = accountStore.accounts.map(\.currency)
        }
        return Set(
            accountCurrencies +
            transactionStore.transactions.map(\.currency) +
            [isAllAccounts ? budgetStore.budget?.currency : nil].compactMap { $0 }
        )
    }

    private var isAllAccounts: Bool {
        accountStore.selectedAccountID == nil
    }

    private var canOpenBudget: Bool {
        isAllAccounts && budgetStore.state != .loading && exchangeRateStore.supports(
            exchangeCurrencies,
            reportingCurrency: dashboardCurrency
        ) && (budgetStore.budget == nil || convertedBudget != nil)
    }

    private var monthTransactions: [FinanceTransaction] {
        let calendar = Calendar.current
        let start = BudgetMonth.start(of: selectedMonth, calendar: calendar)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return transactionStore.transactions.filter { $0.occurredAt >= start && $0.occurredAt < end }
    }

    private var earliestMonth: Date {
        Calendar.current.date(byAdding: .month, value: -12, to: BudgetMonth.start(of: .now)) ?? selectedMonth
    }

    private var latestMonth: Date {
        Calendar.current.date(byAdding: .month, value: 2, to: BudgetMonth.start(of: .now)) ?? selectedMonth
    }

    private var monthTitle: String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: .now)
        let selectedYear = calendar.component(.year, from: selectedMonth)
        return selectedYear == currentYear
            ? selectedMonth.formatted(.dateTime.month(.wide))
            : selectedMonth.formatted(.dateTime.month(.abbreviated).year())
    }

    private var budgetScopeKey: String {
        "\(accountStore.selectedAccountID?.uuidString ?? "all"):\(BudgetMonth.key(for: selectedMonth))"
    }

    private var exchangeRateScopeKey: String {
        "\(dashboardCurrency):\(exchangeCurrencies.sorted().joined(separator: ","))"
    }

    private func loadBudget(force: Bool = false) async {
        // Account summaries use activity only; the budget belongs to All accounts.
        guard isAllAccounts else { return }
        await budgetStore.loadBudget(month: selectedMonth, accountID: nil, force: force)
    }

    private func reload() async {
        async let transactions: Void = transactionStore.loadTransactions(
            accountID: accountStore.selectedAccountID
        )
        async let budget: Void = loadBudget(force: true)
        async let rates: Void = exchangeRateStore.load(
            currencies: exchangeCurrencies,
            reportingCurrency: dashboardCurrency,
            force: true
        )
        _ = await (transactions, budget, rates)
    }
}

private enum DashboardSummaryRegion: Hashable {
    case summary
    case highlights
}

private struct DashboardSummaryBoundsKey: PreferenceKey {
    static let defaultValue: [DashboardSummaryRegion: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [DashboardSummaryRegion: Anchor<CGRect>],
        nextValue: () -> [DashboardSummaryRegion: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct MonthlyActivitySummaryView: View {
    let insights: DashboardInsights
    let monthTitle: String
    let isCurrentMonth: Bool
    let currency: String
    let showsBudgetSettings: Bool
    let canSetBudget: Bool
    let setBudget: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        MonthlySummaryCard(monthTitle: monthTitle) {
            if showsBudgetSettings {
                setBudgetButton
            }
        } content: {
            MonthlySummaryContent {
                if hasNoActivity {
                    Text("No activity yet")
                        .font(.title3.weight(.semibold))
                } else {
                    MonthlySummaryAmount(
                        amount: amountText,
                        suffix: insights.income == 0 ? "spent" : ""
                    )
                }
            } caption: {
                if hasNoActivity {
                    Text("Your monthly summary will appear here")
                } else {
                    Text(isCurrentMonth ? "this month" : "in \(monthTitle)")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summaryAccessibilityLabel)
        }
    }

    private var setBudgetButton: some View {
        // Reserve the same text height as a status, while keeping a 44-point tap target.
        Text("Set budget")
            .hidden()
            .overlay {
                Button(action: setBudget) {
                    Text("Set budget")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .tint(.primary)
                .disabled(!canSetBudget)
                .opacity(canSetBudget ? 1 : 0.45)
                .accessibilityHint("Open budget settings")
            }
    }

    private var hasNoActivity: Bool {
        insights.income == 0 && insights.spent == 0
    }

    private var amountText: String {
        MoneyFormatter.format(
            insights.income == 0 ? insights.spent : insights.net,
            currency: currency,
            showPositiveSign: insights.income != 0
        )
    }

    private var summaryAccessibilityLabel: String {
        if hasNoActivity {
            return String(localized: "No activity yet. Your monthly summary will appear here")
        }
        let amount = MoneyFormatter.spoken(
            insights.income == 0 ? insights.spent : insights.net,
            currency: currency, locale: locale
        )
        return insights.income == 0
            ? String(localized: "\(amount) spent in \(monthTitle)")
            : String(localized: "Net income of \(amount) in \(monthTitle)")
    }
}

private struct DashboardSectionMargins: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.listSectionMargins(.vertical, 0)
        } else {
            content
        }
    }
}

private struct DashboardMonthPicker: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: Date
    let range: ClosedRange<Date>

    @State private var displayedYear: Int

    private let calendar = Calendar.current
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    init(selection: Binding<Date>, range: ClosedRange<Date>) {
        _selection = selection
        self.range = range
        _displayedYear = State(
            initialValue: Calendar.current.component(.year, from: selection.wrappedValue)
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    displayedYear -= 1
                } label: {
                    AppIcon("nav-arrow-left")
                        .frame(width: 32, height: 32)
                }
                .disabled(displayedYear <= earliestYear)
                .accessibilityLabel("Previous year")

                Spacer()

                Text(verbatim: String(displayedYear))
                    .font(.headline)

                Spacer()

                Button {
                    displayedYear += 1
                } label: {
                    AppIcon("nav-arrow-right")
                        .frame(width: 32, height: 32)
                }
                .disabled(displayedYear >= latestYear)
                .accessibilityLabel("Next year")
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(months, id: \.self) { month in
                    AccentSelectionButton(
                        month.formatted(.dateTime.month(.abbreviated)),
                        isSelected: isSelected(month)
                    ) {
                        selection = month
                        dismiss()
                    }
                    .disabled(!isAvailable(month))
                    .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            displayedYear = calendar.component(.year, from: selection)
        }
    }

    private var earliestYear: Int {
        calendar.component(.year, from: range.lowerBound)
    }

    private var latestYear: Int {
        calendar.component(.year, from: range.upperBound)
    }

    private var months: [Date] {
        (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: displayedYear, month: month, day: 1))
        }
    }

    private func isAvailable(_ month: Date) -> Bool {
        month >= range.lowerBound && month <= range.upperBound
    }

    private func isSelected(_ month: Date) -> Bool {
        calendar.isDate(month, equalTo: selection, toGranularity: .month)
    }
}

private extension FinanceTransaction {
    func replacingAmount(_ amount: String, currency: String) -> FinanceTransaction {
        FinanceTransaction(
            id: id,
            accountId: accountId,
            kind: kind,
            amount: amount,
            currency: currency,
            category: category,
            merchant: merchant,
            payee: payee,
            note: note,
            occurredAt: occurredAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            recurrence: recurrence
        )
    }
}

private extension MonthlyBudget {
    @MainActor
    func converted(to currency: String, using rates: ExchangeRateStore) -> MonthlyBudget? {
        guard self.currency.caseInsensitiveCompare(currency) != .orderedSame else {
            return self
        }

        func convert(_ amount: String) -> String? {
            guard let decimal = Decimal(
                string: amount,
                locale: Locale(identifier: "en_US_POSIX")
            ), let converted = rates.convert(
                decimal,
                from: self.currency,
                to: currency
            ) else {
                return nil
            }
            var value = converted
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 4, .bankers)
            return NSDecimalNumber(decimal: rounded).stringValue
        }

        let convertedLimit: String?
        if let monthlyLimit {
            guard let value = convert(monthlyLimit) else { return nil }
            convertedLimit = value
        } else {
            convertedLimit = nil
        }

        let convertedGroups = groups.compactMap { group -> BudgetGroup? in
            guard let limit = convert(group.limit) else { return nil }
            return BudgetGroup(
                id: group.id,
                name: group.name,
                limit: limit,
                sortOrder: group.sortOrder
            )
        }
        guard convertedGroups.count == groups.count else { return nil }

        let convertedAssignments = categoryAssignments.compactMap {
            assignment -> BudgetCategoryAssignment? in
            guard let currentLimit = assignment.limit else {
                return BudgetCategoryAssignment(
                    categoryId: assignment.categoryId,
                    groupId: assignment.groupId,
                    limit: nil
                )
            }
            guard let limit = convert(currentLimit) else { return nil }
            return BudgetCategoryAssignment(
                categoryId: assignment.categoryId,
                groupId: assignment.groupId,
                limit: limit
            )
        }
        guard convertedAssignments.count == categoryAssignments.count else { return nil }

        return MonthlyBudget(
            id: id,
            accountId: accountId,
            month: month,
            currency: currency,
            monthlyLimit: convertedLimit,
            groups: convertedGroups,
            categoryAssignments: convertedAssignments,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
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
