import SwiftUI

struct DebtsView: View {
    private struct RecipientGroup: Identifiable {
        let id: UUID?
        let recipient: Debt?
        let transactions: [FinanceTransaction]
        var name: String { recipient?.name ?? "Unknown recipient" }
    }

    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage(AppPreferences.defaultCurrencyKey) private var currency = AppPreferences.initialCurrency
    @StateObject private var rates = ExchangeRateStore()
    @State private var isAdding = false
    @State private var isCreatingRecipient = false
    @State private var isManagingRecipients = false
    @State private var returningTransaction: FinanceTransaction?
    @State private var editingTransaction: FinanceTransaction?
    @State private var deletingIDs: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        AppList(usesScrollEdgeFades: false) {
            AppSection {
                summary
            }
            .modifier(FinanceSectionMargins())

            if transactionStore.debtTransactions.isEmpty {
                ContentUnavailableView {
                    Label("No outstanding debts", icon: "user")
                } description: {
                    Text("Track money you lend and see how much each person owes you.")
                } actions: {
                    PrimaryActionButton("Lend money", appearance: .prominent) { isAdding = true }
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(recipientGroups) { group in
                    AppSection {
                        recipientSummary(group)
                        ForEach(group.transactions) { transaction in
                            debtRow(transaction)
                        }
                    } header: {
                        Text(group.name)
                    }
                }
            }
            FinanceListBottomSpacer()
        }
        .animateListChanges(value: transactionStore.allTransactions.map(\.id))
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(AppSpacing.large))
        .financePage()
        .navigationTitle("Debts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Group {
                    Menu {
                        Button { isAdding = true } label: { Label("Lend money", icon: "plus") }
                        Button("Manage recipients") { isManagingRecipients = true }
                        Button { isCreatingRecipient = true } label: { Label("New recipient", icon: "user") }
                    } label: { Label("Add debt", icon: "plus") }
                }
                .legacyToolbarControl()
            }
        }
        .task {
            if transactionStore.state != .loaded, transactionStore.state != .loading {
                await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
            }
            await transactionStore.loadDebts()
        }
        .task(id: rateScope) {
            await rates.load(currencies: Set(currencies), reportingCurrency: currency)
        }
        .sheet(isPresented: $isManagingRecipients) { DebtRecipientsView() }
        .sheet(isPresented: $isAdding) { AddTransactionView(initialKind: .debt) }
        .sheet(isPresented: $isCreatingRecipient) { DebtEditorView { _ in } }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(transaction: transaction)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Has the money been returned?", isPresented: Binding(
            get: { returningTransaction != nil },
            set: { if !$0 { returningTransaction = nil } }
        ), titleVisibility: .visible) {
            if let transaction = returningTransaction {
                Button("Delete debt · money returned", role: .destructive) {
                    Task { await markReturned(transaction) }
                }
            }
            Button("Cancel", role: .cancel) { returningTransaction = nil }
        } message: {
            Text("This removes the debt and restores the amount to the original account’s balance.")
        }
        .alert("Couldn’t delete debt", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Try again.") }
    }

    private func debtRow(_ transaction: FinanceTransaction) -> some View {
        Button { editingTransaction = transaction } label: {
            TransactionRow(
                transaction: transaction,
                account: accountStore.accounts.first { $0.id == transaction.accountId },
                timestampStyle: .dateAndTime
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit debt transaction")
        .disabled(deletingIDs.contains(transaction.id))
        .opacity(deletingIDs.contains(transaction.id) ? 0.5 : 1)
        .circleSwipeActions(isEnabled: !deletingIDs.contains(transaction.id)) {
            CircleSwipeAction(title: "Delete · returned", icon: "trash") {
                returningTransaction = transaction
            }
        }
        .contextMenu {
            Button("Delete · money returned", role: .destructive) {
                returningTransaction = transaction
            }
            .disabled(deletingIDs.contains(transaction.id))
        }
    }

    private var currencies: [String] {
        Set(transactionStore.debtTransactions.map { $0.currency.uppercased() }).sorted()
    }

    private var rateScope: String { "\(currency):\(currencies.joined(separator: ","))" }

    private var recipientGroups: [RecipientGroup] {
        let grouped: [UUID?: [FinanceTransaction]] = Dictionary(grouping: transactionStore.debtTransactions) {
            $0.debtId ?? $0.debt?.id
        }
        let groups: [RecipientGroup] = grouped.map { entry in
            let recipient = entry.key.flatMap { id in transactionStore.debts.first { $0.id == id } }
                ?? entry.value.compactMap(\.debt).first
            let transactions = entry.value.sorted { $0.occurredAt > $1.occurredAt }
            return RecipientGroup(id: entry.key, recipient: recipient, transactions: transactions)
        }
        return groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private var summary: some View {
        if let total = transactionStore.outstandingDebt(currency: currency, rates: rates.snapshot) {
            FinanceHighlightCard(title: "Owed to you", amount: total, currency: currency, detail: "Across all accounts") {
                Divider()
                MonthlySummaryRow {
                    Text("\(recipientGroups.count) \(recipientGroups.count == 1 ? "recipient" : "recipients")")
                } trailing: {
                    Text("\(transactionStore.debtTransactions.count) \(transactionStore.debtTransactions.count == 1 ? "transaction" : "transactions")")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text("Swipe a transaction to mark the money as returned.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if transactionStore.state == .loaded {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Owed to you").font(.headline)
                ForEach(currencies, id: \.self) { code in
                    if let total = transactionStore.outstandingDebtInCurrency(code) {
                        Text(MoneyFormatter.format(total, currency: code, roundToWhole: roundTotals))
                            .font(.title2.weight(.semibold)).monospacedDigit()
                    }
                }
                Text("Shown by currency until exchange rates are available.")
                    .font(.caption).foregroundStyle(.secondary)

            }
            .padding(.vertical, AppSpacing.small)
        } else {
            FinanceSummaryUnavailable(state: transactionStore.state, rateState: rates.state)
        }
    }

    private func recipientSummary(_ group: RecipientGroup) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            if let recipient = group.recipient { DebtIcon(debt: recipient) }
            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                Text("Outstanding").font(.subheadline).foregroundStyle(.secondary)
                if let converted = FinanceOverviewData.converted(group.transactions, to: currency, using: rates) {
                    Text(MoneyFormatter.format(
                        converted.reduce(Decimal.zero) { $0 + (Decimal(string: $1.amount) ?? 0) },
                        currency: currency, roundToWhole: roundTotals
                    ))
                    .font(.title3.weight(.semibold)).monospacedDigit()
                } else {
                    ForEach(Set(group.transactions.map(\.currency)).sorted(), id: \.self) { code in
                        let amount = group.transactions.filter { $0.currency == code }
                            .reduce(Decimal.zero) { $0 + (Decimal(string: $1.amount) ?? 0) }
                        Text(MoneyFormatter.format(amount, currency: code, roundToWhole: roundTotals))
                            .font(.headline).monospacedDigit()
                    }
                }
            }
        }
        .padding(.vertical, AppSpacing.small)
        .accessibilityElement(children: .combine)
    }

    private func refresh() async {
        await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        await transactionStore.loadDebts()
        await rates.load(currencies: Set(currencies), reportingCurrency: currency)
    }

    private func markReturned(_ transaction: FinanceTransaction) async {
        guard deletingIDs.insert(transaction.id).inserted else { return }
        defer { deletingIDs.remove(transaction.id) }
        do {
            try await transactionStore.deleteTransaction(transaction)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
