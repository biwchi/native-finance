import SwiftUI

struct RecurringTransactionsView: View {
    var allAccounts = false
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppPreferences.defaultCurrencyKey) private var reportingCurrency = AppPreferences.initialCurrency
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @StateObject private var rates = ExchangeRateStore()
    @State private var isAdding = false
    @State private var editingTransaction: UpcomingTransaction?
    @State private var editingRecordedTransaction: FinanceTransaction?
    @State private var deletingTransaction: UpcomingTransaction?
    @State private var deletingTransactionID: UUID?
    @State private var errorMessage: String?
    @State private var kindFilter = RecurringForecast.KindFilter.expenses
    @State private var period = RecurringForecast.Period.month
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 48

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                Section {
                    summary(at: context.date)
                }
                .modifier(FinanceSectionMargins())

                if transactionStore.upcomingState == .loaded, filteredUpcomingTransactions.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(emptyStateTitle, icon: "repeat")
                        } description: {
                            Text("Set up bills, subscriptions or regular income to see what’s ahead.")
                        } actions: {
                            PrimaryActionButton("Add recurring transaction", appearance: .prominent) {
                                isAdding = true
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        UpcomingTransactionsContent(
                            allAccounts: allAccounts,
                            kindFilter: kindFilter.transactionKind,
                            isDeleting: deletingTransactionID != nil,
                            onEdit: { editingTransaction = $0 },
                            onDelete: { deletingTransaction = $0 }
                        )
                    } header: {
                        Text("Active schedules")
                    } footer: {
                        Text("Tap a schedule to edit or stop repeating.")
                    }
                }
                recordedTransactionsSection(now: context.date)
                FinanceListBottomSpacer()
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(AppSpacing.large))
            .financePage(usesNativeNavigationTitle: true)
        }
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.large)
        .modifier(RecurringAccountsToolbar(allAccounts: allAccounts))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Add recurring transaction", icon: "plus")
                }
            }
        }
        .refreshable { await refresh() }
        .task {
            switch transactionStore.state {
            case .idle, .failed:
                await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
            case .loaded:
                if upcomingTransactions.contains(where: { $0.occurredAt < .now }) {
                    await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
                } else if transactionStore.upcomingState != .loaded, transactionStore.upcomingState != .loading {
                    await transactionStore.loadUpcomingTransactions(accountID: accountStore.selectedAccountID)
                }
            case .loading:
                break
            }
        }
        .task(id: rateScope) {
            await rates.load(currencies: currencies, reportingCurrency: currency)
        }
        .sheet(isPresented: $isAdding) {
            AddTransactionView(initialKind: kindFilter.transactionKind ?? .expense, initialRecurring: true)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingRecordedTransaction) { transaction in
            AddTransactionView(transaction: transaction)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(upcomingTransaction: transaction)
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(errorMessage == nil ? "Choose an action" : "Couldn’t update recurring transaction", isPresented: alertBinding) {
            if errorMessage != nil {
                Button("OK", role: .cancel) {}
            } else if let transaction = deletingTransaction {
                RecurringDeletionActions { action in
                    Task { await delete(transaction, action: action) }
                }
            }
        } message: {
            Text(errorMessage ?? "This is a recurring transaction. What would you like to delete?")
        }
    }

    private var upcomingTransactions: [UpcomingTransaction] {
        allAccounts ? transactionStore.allUpcomingTransactions : transactionStore.upcomingTransactions
    }

    private var currency: String {
        allAccounts ? reportingCurrency.uppercased() : accountStore.selectedAccount?.currency ?? reportingCurrency.uppercased()
    }

    private var filteredUpcomingTransactions: [UpcomingTransaction] {
        upcomingTransactions.filter { kindFilter.includes($0.kind) }
    }

    private var emptyStateTitle: String {
        switch kindFilter {
        case .expenses: "No recurring expenses"
        case .income: "No recurring income"
        case .all: "No recurring transactions"
        }
    }

    private var currencies: Set<String> { Set(filteredUpcomingTransactions.map(\.currency)) }
    private var rateScope: String { "\(currency):\(currencies.sorted().joined(separator: ","))" }

    private func summary(at now: Date) -> some View {
        VStack(spacing: AppSpacing.doubleExtraLarge) {
            Picker("Transaction type", selection: $kindFilter) {
                ForEach(RecurringForecast.KindFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("recurringKindFilter")

            if transactionStore.upcomingState == .loaded,
               let totals = RecurringForecast.calculate(
                   upcoming: upcomingTransactions, period: period, filter: kindFilter,
                   now: now, calendar: calendar,
                   convert: { rates.convert($0, from: $1, to: currency) }
               ) {
                summaryAmount(kindFilter.amount(from: totals))
            } else {
                VStack(spacing: AppSpacing.small) {
                    FinanceSummaryUnavailable(state: transactionStore.upcomingState, rateState: rates.state)
                    if case .failed = rates.state {
                        Button("Retry exchange rates") {
                            Task { await rates.load(currencies: currencies, reportingCurrency: currency, force: true) }
                        }
                    }
                }
            }

            Picker("Forecast period", selection: $period) {
                ForEach(RecurringForecast.Period.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("recurringPeriodFilter")
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, AppSpacing.small)
        .frame(maxWidth: .infinity)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func summaryAmount(_ amount: Decimal) -> some View {
        VStack(spacing: AppSpacing.extraSmall) {
            Text(MoneyFormatter.format(
                amount, currency: currency, showPositiveSign: kindFilter == .all, roundToWhole: roundTotals
            ))
            .font(.system(size: amountSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText(value: NSDecimalNumber(decimal: amount).doubleValue))
            .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: amount)
            .accessibilityIdentifier("recurringSummaryAmount")
            .accessibilityLabel(MoneyFormatter.spoken(
                amount, currency: currency, locale: locale, roundToWhole: roundTotals
            ))
            Text("\(kindFilter.amountTitle) · \(period.description)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.small)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func recordedTransactionsSection(now: Date) -> some View {
        let transactions = (allAccounts ? transactionStore.allTransactions : transactionStore.transactions)
            .filter { $0.recurrence != nil && $0.occurredAt <= now && kindFilter.includes($0.kind) }
            .sorted { $0.occurredAt > $1.occurredAt }
        Section("Recorded transactions") {
            switch transactionStore.state {
            case .idle, .loading:
                ProgressView("Loading transactions").frame(maxWidth: .infinity)
            case .failed:
                Button("Retry transaction history") { Task { await refresh() } }
            case .loaded:
                if transactions.isEmpty {
                    Text("Completed recurring transactions will appear here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(transactions) { transaction in
                    Button { editingRecordedTransaction = transaction } label: {
                        TransactionRow(
                            transaction: transaction,
                            account: accountStore.accounts.first { $0.id == transaction.accountId },
                            timestampStyle: .dateAndTime
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit recorded transaction")
                }
            }
        }
    }

    private func refresh() async {
        await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        await rates.load(currencies: currencies, reportingCurrency: currency, force: true)
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { deletingTransaction != nil || errorMessage != nil },
            set: {
                if !$0 {
                    deletingTransaction = nil
                    errorMessage = nil
                }
            }
        )
    }

    private func delete(_ transaction: UpcomingTransaction, action: RecurringDeletionAction) async {
        deletingTransactionID = transaction.id
        defer { deletingTransactionID = nil }
        do {
            try await transactionStore.deleteUpcomingTransaction(transaction, action: action)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
