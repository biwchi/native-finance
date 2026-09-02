import SwiftUI

struct DashboardView: View {
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

    var body: some View {
        NavigationStack {
            List {

                monthlyBudgetProgressSection

                monthlyHighlightsSection

                recentTransactionsSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(10))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountSelector(compact: true)
                }

                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarLeading)
                }

                ToolbarItem(placement: .topBarLeading) {
                    budgetSettingsButton
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingMonthPicker = true
                    } label: {
                        Image(systemName: "calendar")
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
            }
            .refreshable { await reload() }
        }
        .task(id: budgetScopeKey) {
            await budgetStore.loadBudget(
                month: selectedMonth,
                accountID: accountStore.selectedAccountID
            )
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
    }

    private var budgetSettingsButton: some View {
        Button {
            isShowingBudgetSettings = true
        } label: {
            Image(systemName: "chart.pie")
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
                    Label(message, systemImage: "exclamationmark.triangle")
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
                            Label(message, systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.secondary)
                        case .loaded:
                            Label(
                                "Some currencies could not be converted",
                                systemImage: "exclamationmark.triangle"
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

    private func money(_ value: Decimal, currency: String) -> String {
        value.formatted(
            .currency(code: currency)
                .precision(.fractionLength(0...2))
        )
    }

    @ViewBuilder
    private var monthlyBudgetProgressSection: some View {
        if transactionStore.state == .loaded,
           budgetStore.state == .loaded,
           let insights,
           let monthlyLimit = insights.monthlyLimit,
           let progress = insights.budgetProgress {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    budgetProgressBar(progress: progress)
                        .animation(.smooth, value: progress)
                        .accessibilityLabel("Monthly budget used")
                        .accessibilityValue(
                            "\(money(insights.spent, currency: dashboardCurrency)) of \(money(monthlyLimit, currency: dashboardCurrency))"
                        )

                    HStack {
                        Text("Monthly limit")
                            .foregroundStyle(.secondary)
                            .fontWeight(.bold)
                            .font(.system(size: 14))

                        Spacer()

                        HStack(spacing: 0) {
                            Text(money(insights.spent, currency: dashboardCurrency))
                                .fontWeight(.semibold)
                            Text(" / \(money(monthlyLimit, currency: dashboardCurrency))")
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 6)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func clampedBudgetProgress(_ progress: Decimal) -> Double {
        min(max(NSDecimalNumber(decimal: progress).doubleValue, 0), 1)
    }

    private func budgetProgressTint(for progress: Decimal) -> Color {
        let value = clampedBudgetProgress(progress)
        guard value < 1 else { return .red }
        guard value >= 0.7 else { return .accentColor }

        let proximityToLimit = (value - 0.7) / 0.3
        return Color(
            hue: 0.09 * (1 - proximityToLimit),
            saturation: 0.88,
            brightness: 0.92
        )
    }

    private func budgetProgressBar(progress: Decimal) -> some View {
        let value = clampedBudgetProgress(progress)
        let tint = budgetProgressTint(for: progress)

        return GeometryReader { geometry in
            let horizontalInset: CGFloat = 4
            let innerInset: CGFloat = 5
            let markerDiameter: CGFloat = 22
            let trackWidth = max(geometry.size.width - horizontalInset * 2, 0)
            let availableWidth = max(trackWidth - markerDiameter, 0)
            let markerCenter = markerDiameter / 2 + availableWidth * CGFloat(value)
            let fillWidth = max(markerCenter - innerInset, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .overlay {
                        Capsule()
                            .stroke(.secondary.opacity(0.08), lineWidth: 1)
                    }

                Canvas { context, size in
                    var stripes = Path()
                    for startX in stride(
                        from: -size.height,
                        through: size.width + size.height,
                        by: 6
                    ) {
                        stripes.move(to: CGPoint(x: startX, y: size.height))
                        stripes.addLine(to: CGPoint(x: startX + size.height, y: 0))
                    }
                    context.stroke(
                        stripes,
                        with: .color(tint.opacity(0.28)),
                        lineWidth: 1.5
                    )
                }
                .frame(height: 12)
                .clipShape(Capsule())
                .padding(.horizontal, innerInset)

                Capsule()
                    .fill(tint)
                    .frame(width: value == 0 ? 0 : fillWidth, height: 12)
                    .offset(x: innerInset)

                if value > 0 {
                    Circle()
                        .fill(tint)
                        .frame(width: markerDiameter, height: markerDiameter)
                        .overlay {
                            Circle()
                                .stroke(
                                    Color(uiColor: .secondarySystemGroupedBackground),
                                    lineWidth: 3
                                )
                        }
                        .offset(x: markerCenter - markerDiameter / 2)
                }
            }
            .frame(width: trackWidth, height: 24)
            .clipShape(Capsule())
            .offset(x: horizontalInset)
        }
        .frame(height: 24)
        .clipped()
    }

    @ViewBuilder
    private var monthlyHighlightsSection: some View {
        if transactionStore.state == .loaded,
           budgetStore.state == .loaded,
           let insights {
            Section {
                HStack(spacing: 10) {
                    if insights.income > 0 { monthlyHighlight(
                        title: "Income",
                        amount: insights.income,
                        systemImage: "arrow.down.left",
                        color: .green,
                        amountColor: .green
                    )
                    }

                    if insights.spent > 0 { monthlyHighlight(
                        title: "Spent",
                        amount: insights.spent,
                        systemImage: "arrow.up.right",
                        color: .orange,
                        amountColor: .primary
                    )
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private func monthlyHighlight(
        title: String,
        amount: Decimal,
        systemImage: String,
        color: Color,
        amountColor: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .background(color.opacity(0.2), in: Circle())

            Text(money(amount, currency: dashboardCurrency))
                .font(.body.weight(.semibold))
                .foregroundStyle(amountColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(money(amount, currency: dashboardCurrency))
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
        guard let budget = budgetStore.budget else { return nil }
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
            [budgetStore.budget?.currency].compactMap { $0 }
        )
    }

    private var canOpenBudget: Bool {
        budgetStore.state != .loading && exchangeRateStore.supports(
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

    private func reload() async {
        async let transactions: Void = transactionStore.loadTransactions(
            accountID: accountStore.selectedAccountID
        )
        async let budget: Void = budgetStore.loadBudget(
            month: selectedMonth,
            accountID: accountStore.selectedAccountID,
            force: true
        )
        async let rates: Void = exchangeRateStore.load(
            currencies: exchangeCurrencies,
            reportingCurrency: dashboardCurrency,
            force: true
        )
        _ = await (transactions, budget, rates)
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
                    Image(systemName: "chevron.left")
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
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .disabled(displayedYear >= latestYear)
                .accessibilityLabel("Next year")
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(months, id: \.self) { month in
                    Button {
                        selection = month
                        dismiss()
                    } label: {
                        Text(month.formatted(.dateTime.month(.abbreviated)))
                            .font(.subheadline.weight(isSelected(month) ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(isSelected(month) ? .white : .primary)
                            .background(
                                isSelected(month) ? Color.accentColor : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isAvailable(month))
                    .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
                    .accessibilityAddTraits(isSelected(month) ? .isSelected : [])
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
        icon: "creditcard.fill",
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
        icon: "fork.knife",
        color: .orange
    )
    static let housing = category(
        systemKey: "expense.housing",
        name: "Housing",
        icon: "house.fill",
        color: .blue
    )
    static let shopping = category(
        systemKey: "expense.shopping",
        name: "Shopping",
        icon: "bag.fill",
        color: .purple
    )
    static let salary = TransactionCategory(
        id: UUID(),
        systemKey: "income.salary",
        name: "Salary",
        kind: .income,
        icon: "banknote.fill",
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
