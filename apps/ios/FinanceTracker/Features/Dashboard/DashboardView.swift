import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @EnvironmentObject private var transactionStore: TransactionStore

    @State private var selectedMonth = BudgetMonth.start(of: .now)
    @State private var isShowingBudgetSettings = false
    @State private var editingTransaction: FinanceTransaction?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    highlightContent
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                recentTransactionsSection
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountSelector(compact: true)
                }

                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarLeading)
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingBudgetSettings = true
                    } label: {
                        Image(systemName: budgetStore.budget == nil ? "chart.pie" : "chart.pie.fill")
                    }
                    .disabled(dashboardCurrency == nil)
                    .accessibilityLabel("Budget settings")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    monthControl
                }
            }
            .refreshable { await reload() }
        }
        .task(id: budgetScopeKey) {
            await budgetStore.loadBudget(
                month: selectedMonth,
                accountID: accountStore.selectedAccountID
            )
        }
        .sheet(isPresented: $isShowingBudgetSettings) {
            if let dashboardCurrency {
                BudgetSettingsView(
                    month: selectedMonth,
                    accountID: accountStore.selectedAccountID,
                    currency: dashboardCurrency,
                    budget: budgetStore.budget
                )
                .environmentObject(budgetStore)
                .environmentObject(transactionStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(transaction: transaction)
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var highlightContent: some View {
        if let currency = dashboardCurrency {
            switch transactionStore.state {
            case .idle, .loading:
                DashboardHighlightPlaceholder()
            case .loaded:
                DashboardHighlightCard(
                    insights: insights,
                    transactions: monthTransactions,
                    currency: currency,
                    month: selectedMonth,
                    isBudgetLoading: budgetStore.state == .loading
                )
            case let .failed(message):
                DashboardMessageCard(
                    title: "Highlights unavailable",
                    message: message,
                    systemImage: "chart.line.downtrend.xyaxis"
                )
            }
        } else {
            DashboardMessageCard(
                title: accountStore.accounts.isEmpty ? "Add your first account" : "Choose one currency",
                message: accountStore.accounts.isEmpty
                    ? "Your monthly highlights and budgets will live here."
                    : "Select an account to see accurate monthly totals and create its budget.",
                systemImage: accountStore.accounts.isEmpty ? "creditcard.fill" : "arrow.triangle.2.circlepath"
            )
        }
    }

    @ViewBuilder
    private var recentTransactionsSection: some View {
        switch transactionStore.state {
        case .idle, .loading:
            Section("Latest transactions") {
                ProgressView("Loading transactions")
                    .frame(maxWidth: .infinity)
            }
        case .loaded:
            Section("Latest transactions") {
                if monthTransactions.isEmpty {
                    ContentUnavailableView(
                        "No transactions",
                        systemImage: "calendar.badge.minus",
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
            }
        case .failed:
            EmptyView()
        }
    }

    private var monthControl: some View {
        HStack(spacing: 10) {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.bold())
            }
            .disabled(!canMoveToPreviousMonth)
            .accessibilityLabel("Previous month")

            Text(monthTitle)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 76)
                .contentTransition(.numericText())

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
            }
            .disabled(!canMoveToNextMonth)
            .accessibilityLabel("Next month")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Month, \(monthTitle)")
    }

    private var insights: DashboardInsights {
        DashboardInsights.calculate(
            transactions: transactionStore.transactions,
            month: selectedMonth,
            monthlyLimit: budgetStore.budget?.monthlyLimit.flatMap { Decimal(string: $0) }
        )
    }

    private var dashboardCurrency: String? {
        if let account = accountStore.selectedAccount {
            return account.currency
        }

        let currencies = Set(accountStore.accounts.map(\.currency))
        return currencies.count == 1 ? currencies.first : nil
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

    private var canMoveToPreviousMonth: Bool {
        selectedMonth > earliestMonth
    }

    private var canMoveToNextMonth: Bool {
        selectedMonth < latestMonth
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

    private func moveMonth(by value: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else {
            return
        }
        selectedMonth = BudgetMonth.start(of: month)
    }

    private func reload() async {
        async let transactions: Void = transactionStore.loadTransactions(
            accountID: accountStore.selectedAccountID
        )
        async let budget: Void = budgetStore.loadBudget(
            month: selectedMonth,
            accountID: accountStore.selectedAccountID,
            force: true
        )
        _ = await (transactions, budget)
    }
}

private struct DashboardHighlightCard: View {
    let insights: DashboardInsights
    let transactions: [FinanceTransaction]
    let currency: String
    let month: Date
    let isBudgetLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 4) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())

                Text(subheadline)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            spendingChart
        }
        .dashboardCardStyle()
        .overlay(alignment: .topTrailing) {
            if isBudgetLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(18)
            }
        }
    }

    private var spendingChart: some View {
        Chart {
            ForEach(budgetPacePoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Budget pace", point.amount),
                    series: .value("Series", "Budget")
                )
                .foregroundStyle(Color.accentColor.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 6]))
            }

            ForEach(spendingPoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Baseline", 0),
                    yEnd: .value("Spent", point.amount)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [spendingColor.opacity(0.22), spendingColor.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }

            ForEach(spendingSegments) { segment in
                LineMark(
                    x: .value("Date", segment.start.date),
                    y: .value("Spent", segment.start.amount),
                    series: .value("Series", "Spent-\(segment.id)")
                )
                .foregroundStyle(segment.color)
                .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Date", segment.end.date),
                    y: .value("Spent", segment.end.amount),
                    series: .value("Series", "Spent-\(segment.id)")
                )
                .foregroundStyle(segment.color)
                .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            if let latestPoint = spendingPoints.last {
                PointMark(
                    x: .value("Date", latestPoint.date),
                    y: .value("Spent", latestPoint.amount)
                )
                .foregroundStyle(spendingColor)
                .symbol {
                    Circle()
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .stroke(spendingColor, lineWidth: 3)
                        .frame(width: 12, height: 12)
                }
                .annotation(position: .bottom, alignment: .trailing, spacing: 8) {
                    if let paceLabel {
                        Text(paceLabel)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(paceLabelForeground)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                spendingColor,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                    }
                }
            }
        }
        .chartXScale(domain: monthStart...chartEnd)
        .chartYScale(domain: chartMinimum...chartMaximum)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly spending chart")
        .accessibilityValue("\(money(insights.spent)) spent; \(subheadline)")
    }

    private var headline: String {
        guard let remaining = insights.remaining else {
            return Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
                ? "\(money(insights.spent)) spent this month"
                : "\(money(insights.spent)) spent"
        }
        return remaining >= 0
            ? "\(money(remaining)) left"
            : "\(money(-remaining)) over budget"
    }

    private var subheadline: String {
        guard let monthlyLimit = insights.monthlyLimit else {
            return "No monthly budget set"
        }
        return "out of \(money(monthlyLimit)) budgeted"
    }

    private var spendingColor: Color {
        spendingPoints.last.map(color(for:)) ?? .accentColor
    }

    private var paceLabelForeground: Color {
        guard let monthlyLimit = insights.monthlyLimit, insights.spent > monthlyLimit else {
            return .black.opacity(0.78)
        }
        return .white
    }

    private var paceLabel: String? {
        guard let difference = paceDifference else {
            return nil
        }
        if abs(difference) < 0.01 {
            return "On pace"
        }
        return difference > 0
            ? "\(money(difference)) under"
            : "\(money(-difference)) over"
    }

    private var paceDifference: Decimal? {
        guard let monthlyLimit = insights.monthlyLimit, monthStart <= Date.now else {
            return nil
        }
        let idealSpent = monthlyLimit * Decimal(idealProgress(at: spendingEnd))
        return idealSpent - insights.spent
    }

    private var monthStart: Date {
        BudgetMonth.start(of: month)
    }

    private var chartEnd: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
    }

    private var spendingEnd: Date {
        if monthStart > Date.now {
            return monthStart
        }
        if Calendar.current.isDate(monthStart, equalTo: .now, toGranularity: .month) {
            let startOfToday = Calendar.current.startOfDay(for: .now)
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? Date.now
            return min(tomorrow, chartEnd)
        }
        return chartEnd
    }

    private var spendingPoints: [DashboardChartPoint] {
        var points = [DashboardChartPoint(id: 0, date: monthStart, amount: 0)]
        var runningTotal = Decimal.zero

        let expenses = transactions
            .filter { $0.kind == .expense && $0.occurredAt >= monthStart && $0.occurredAt < chartEnd && $0.occurredAt <= spendingEnd }
            .sorted { $0.occurredAt < $1.occurredAt }

        for transaction in expenses {
            guard let amount = Decimal(string: transaction.amount) else {
                continue
            }
            runningTotal += amount
            points.append(
                DashboardChartPoint(
                    id: points.count,
                    date: transaction.occurredAt,
                    amount: decimalValue(runningTotal)
                )
            )
        }

        if points.last?.date != spendingEnd {
            points.append(
                DashboardChartPoint(
                    id: points.count,
                    date: spendingEnd,
                    amount: decimalValue(runningTotal)
                )
            )
        }
        return points
    }

    private var spendingSegments: [DashboardChartSegment] {
        zip(spendingPoints, spendingPoints.dropFirst()).enumerated().map { index, pair in
            DashboardChartSegment(
                id: index,
                start: pair.0,
                end: pair.1,
                color: color(for: pair.1)
            )
        }
    }

    private var budgetPacePoints: [DashboardChartPoint] {
        guard let monthlyLimit = insights.monthlyLimit else {
            return []
        }
        return [
            DashboardChartPoint(id: 0, date: monthStart, amount: 0),
            DashboardChartPoint(id: 1, date: chartEnd, amount: decimalValue(monthlyLimit))
        ]
    }

    private var chartMaximum: Double {
        let spentMaximum = spendingPoints.map(\.amount).max() ?? 0
        let budgetMaximum = insights.monthlyLimit.map(decimalValue) ?? 0
        return max(spentMaximum, budgetMaximum, 1) * 1.12
    }

    private var chartMinimum: Double {
        -chartMaximum * 0.16
    }

    private func money(_ value: Decimal) -> String {
        value.formatted(
            .currency(code: currency)
                .precision(.fractionLength(0...2))
        )
    }

    private func decimalValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private func idealProgress(at date: Date) -> Double {
        let duration = chartEnd.timeIntervalSince(monthStart)
        guard duration > 0 else {
            return 0
        }
        let elapsed = min(max(date.timeIntervalSince(monthStart), 0), duration)
        return elapsed / duration
    }

    private func color(for point: DashboardChartPoint) -> Color {
        guard let monthlyLimit = insights.monthlyLimit else {
            return .accentColor
        }

        let budget = decimalValue(monthlyLimit)
        guard budget > 0 else {
            return .accentColor
        }

        let usedProgress = point.amount / budget
        if usedProgress > 1 {
            return .red
        }

        let differenceFromIdeal = usedProgress - idealProgress(at: point.date)
        if differenceFromIdeal <= 0 {
            return .green
        }
        if differenceFromIdeal < 0.2 {
            return Color(red: 1, green: 0.64, blue: 0.14)
        }
        return Color(red: 0.93, green: 0.32, blue: 0.06)
    }
}

private struct DashboardChartPoint: Identifiable {
    let id: Int
    let date: Date
    let amount: Double
}

private struct DashboardChartSegment: Identifiable {
    let id: Int
    let start: DashboardChartPoint
    let end: DashboardChartPoint
    let color: Color
}

private struct DashboardHighlightPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView()
            RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.12)).frame(height: 34)
            RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.10)).frame(height: 8)
            RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.08)).frame(height: 58)
        }
        .dashboardCardStyle()
    }
}

private struct DashboardMessageCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .dashboardCardStyle()
    }
}

private extension View {
    func dashboardCardStyle() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
            }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AccountStore())
        .environmentObject(BudgetStore.preview())
        .environmentObject(TransactionStore())
}
