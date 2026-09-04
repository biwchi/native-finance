import Foundation
import SwiftUI

struct TransactionListView: View {
    private enum DetachedContentID: Hashable {
        case overview
        case search
    }

    private struct DetachedContentBoundsPreferenceKey: PreferenceKey {
        static let defaultValue: [DetachedContentID: Anchor<CGRect>] = [:]

        static func reduce(
            value: inout [DetachedContentID: Anchor<CGRect>],
            nextValue: () -> [DetachedContentID: Anchor<CGRect>]
        ) {
            value.merge(nextValue()) { _, next in next }
        }
    }

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @State private var editingTransaction: FinanceTransaction?
    @State private var presentedAlert: TransactionListAlert?
    @State private var deletingTransactionID: UUID?
    @StateObject private var summaryRates = ExchangeRateStore()
    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var reportingCurrency = AppPreferences.initialCurrency
    @State private var selectedMonth: Date
    @Binding private var searchText: String

    var recentLimit: Int?
    var showsOverview: Bool

    init(
        recentLimit: Int? = nil,
        showsOverview: Bool = false,
        month: Date = .now,
        searchText: Binding<String> = .constant("")
    ) {
        self.recentLimit = recentLimit
        self.showsOverview = showsOverview
        _selectedMonth = State(initialValue: BudgetMonth.start(of: month))
        _searchText = searchText
    }

    var body: some View {
        List {
            if showsOverview {
                overviewSection
            }
            switch transactionStore.state {
            case .idle, .loading:
                ProgressView("Loading transactions")
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

            case .loaded:
                if visibleTransactions.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No transactions yet" : "No matching transactions",
                        iconName: "list",
                        description: Text(showsOverview
                            ? (searchText.isEmpty ? "Transactions for the selected month will appear here." : "Try a different merchant, category or amount.")
                            : emptyDescription)
                    )
                    .listRowBackground(Color.clear)
                } else if let recentLimit {
                    Section("Recent transactions") {
                        ForEach(visibleTransactions.prefix(recentLimit)) { transaction in
                            transactionButton(transaction)
                        }
                    }
                } else {
                    ForEach(transactionGroups, id: \.day) { group in
                        Section {
                            ForEach(group.transactions) { transaction in
                                transactionButton(transaction)
                            }
                        } header: {
                            Text(group.day, format: .dateTime.day().month(.wide).year())
                        }
                    }
                }

            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn’t load transactions", icon: "wifi-warning")
                } description: {
                    Text(message)
                } actions: {
                    PrimaryActionButton("Try Again", appearance: .prominent) {
                        Task { await reload() }
                    }
                }
                .listRowBackground(Color.clear)
            }

            if showsOverview {
                FinanceListBottomSpacer()
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(4))
        .environment(\.defaultMinListRowHeight, 0)
        .financePage(
            enabled: showsOverview,
            detachedPreference: DetachedContentBoundsPreferenceKey.self
        ) {
            bounds, proxy in
            ZStack {
                if let anchor = bounds[.overview],
                    transactionStore.state == .loaded,
                    let insights
                {
                    let frame = proxy[anchor]
                    overviewCards(for: insights)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }

                if let anchor = bounds[.search] {
                    let frame = proxy[anchor]
                    TransactionSearchField(text: $searchText)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .modifier(ActivityToolbar(isEnabled: showsOverview, month: $selectedMonth))
        .task(id: rateScope) {
            if showsOverview { await loadRates() }
        }
        .refreshable { await reload() }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(transaction: transaction)
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(presentedAlert?.title ?? "", isPresented: alertBinding, presenting: presentedAlert) { alert in
            switch alert {
            case let .confirmDeletion(transaction):
                if transaction.recurrence != nil {
                    RecurringDeletionActions { action in
                        Task { await delete(transaction, action: action) }
                    }
                } else {
                    Button("Delete", role: .destructive) {
                        Task { await delete(transaction) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            case .error:
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            switch alert {
            case let .confirmDeletion(transaction):
                Text(transaction.recurrence == nil
                     ? "This can't be undone."
                     : "This is a recurring transaction. What would you like to delete?")
            case let .error(message):
                Text(message)
            }
        }
    }

    private var overviewSection: some View {
        Section {
            FinancePageHeader(title: "Activity")
            if transactionStore.state == .loaded, let insights {
                if #available(iOS 26.0, *) {
                    overviewCards(for: insights)
                        .hidden()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .anchorPreference(
                            key: DetachedContentBoundsPreferenceKey.self,
                            value: .bounds
                        ) { [.overview: $0] }
                } else {
                    overviewCards(for: insights)
                }
            } else {
                FinanceSummaryUnavailable(state: transactionStore.state, rateState: summaryRates.state)
            }
            TransactionSearchField(text: $searchText)
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .anchorPreference(
                    key: DetachedContentBoundsPreferenceKey.self,
                    value: .bounds
                ) { [.search: $0] }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .modifier(FinanceSectionMargins())
    }

    private func overviewCards(for insights: DashboardInsights) -> some View {
        FinanceMetricCards(
            first: .init(title: "Spent", amount: insights.spent),
            second: .init(title: "Income", amount: insights.income),
            currency: currency,
            surface: .glass
        )
    }

    private var currency: String { accountStore.selectedAccount?.currency ?? reportingCurrency.uppercased() }
    private var currencies: Set<String> { Set(transactionStore.transactions.map(\.currency)) }
    private var rateScope: String { "\(currency):\(currencies.sorted().joined(separator: ","))" }
    private var insights: DashboardInsights? {
        guard let converted = FinanceOverviewData.converted(transactionStore.transactions, to: currency, using: summaryRates) else { return nil }
        return DashboardInsights.calculate(transactions: converted, month: selectedMonth, monthlyLimit: nil)
    }
    private var visibleTransactions: [FinanceTransaction] {
        guard showsOverview else { return transactionStore.transactions }
        return FinanceOverviewData.transactions(transactionStore.transactions, in: selectedMonth)
            .filter { FinanceOverviewData.matches($0, query: searchText, accounts: accountStore.accounts) }
    }
    private func loadRates(force: Bool = false) async {
        await summaryRates.load(currencies: currencies, reportingCurrency: currency, force: force)
    }

    private func transactionButton(_ transaction: FinanceTransaction) -> some View {
        Button {
            editingTransaction = transaction
        } label: {
            TransactionRow(
                transaction: transaction,
                account: accountStore.accounts.first { $0.id == transaction.accountId },
                timestampStyle: recentLimit == nil ? .time : .dateAndTime
            )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit transaction")
        .disabled(deletingTransactionID != nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                presentedAlert = .confirmDeletion(transaction)
            } label: {
                Label("Delete", icon: "trash")
            }
        }
    }

    private var transactionGroups: [(day: Date, transactions: [FinanceTransaction])] {
        let groups = Dictionary(grouping: visibleTransactions) {
            Calendar.current.startOfDay(for: $0.occurredAt)
        }
        return groups.keys.sorted(by: >).map { (day: $0, transactions: groups[$0] ?? []) }
    }

    private var emptyDescription: String {
        if let account = accountStore.selectedAccount {
            "New transactions for \(account.name) will appear here. Tap + to add one."
        } else {
            "Transactions from all accounts will appear here. Tap + to add one."
        }
    }

    private func reload() async {
        await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        if showsOverview { await loadRates(force: true) }
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { presentedAlert != nil }, set: { if !$0 { presentedAlert = nil } })
    }

    private func delete(_ transaction: FinanceTransaction, action: RecurringDeletionAction = .occurrence) async {
        deletingTransactionID = transaction.id
        defer { deletingTransactionID = nil }

        do {
            try await transactionStore.deleteTransaction(transaction, action: action)
        } catch {
            presentedAlert = .error(error.localizedDescription)
        }
    }
}
