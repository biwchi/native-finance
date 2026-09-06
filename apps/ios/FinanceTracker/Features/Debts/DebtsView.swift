import SwiftUI

struct DebtsView: View {
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage(AppPreferences.defaultCurrencyKey) private var currency = AppPreferences.initialCurrency
    @StateObject private var rates = ExchangeRateStore()
    @State private var isAdding = false
    @State private var isCreatingRecipient = false
    @State private var isManagingRecipients = false
    @State private var returningTransaction: FinanceTransaction?
    @State private var deletingIDs: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Total owed to you").font(.subheadline).foregroundStyle(.secondary)
                    if let total = transactionStore.outstandingDebt(currency: currency, rates: rates.snapshot) {
                        Text(MoneyFormatter.format(total, currency: currency, roundToWhole: roundTotals))
                            .font(.largeTitle.bold()).monospacedDigit()
                    } else {
                        Text("Total unavailable").font(.headline)
                        if transactionStore.state == .loaded {
                            ForEach(currencies, id: \.self) { code in
                                if let total = transactionStore.outstandingDebtInCurrency(code) {
                                    Text(MoneyFormatter.format(total, currency: code, roundToWhole: roundTotals)).monospacedDigit()
                                }
                            }
                            Text("Exchange rates are unavailable. Amounts are shown by currency.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Across all accounts. Delete a debt transaction when the money is returned to its original account.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, AppSpacing.small)
            }

            if case let .failed(message) = transactionStore.state {
                Section {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try again") { Task { await refresh() } }
                }
            } else if transactionStore.state == .loading || transactionStore.state == .idle {
                ProgressView("Loading debts")
            } else if transactionStore.debtTransactions.isEmpty {
                ContentUnavailableView("No outstanding debts", iconName: "user",
                    description: Text("Add a debt transaction when you lend someone money."))
            } else {
                Section("Outstanding debt transactions") {
                    ForEach(transactionStore.debtTransactions) { transaction in
                        debtRow(transaction)
                    }
                }
            }
        }
        .navigationTitle("Debts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { isAdding = true } label: { Label("Lend money", icon: "plus") }
                    Button("Manage recipients") { isManagingRecipients = true }
                    Button { isCreatingRecipient = true } label: { Label("New recipient", icon: "user") }
                } label: { Label("Add debt", icon: "plus") }
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
        .task(id: rateScope) {
            await rates.load(currencies: Set(currencies), reportingCurrency: currency)
        }
        .sheet(isPresented: $isManagingRecipients) { DebtRecipientsView() }
        .sheet(isPresented: $isAdding) { AddTransactionView(initialKind: .debt) }
        .sheet(isPresented: $isCreatingRecipient) { DebtEditorView { _ in } }
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
        TransactionRow(
            transaction: transaction,
            account: accountStore.accounts.first { $0.id == transaction.accountId },
            timestampStyle: .dateAndTime
        )
        .opacity(deletingIDs.contains(transaction.id) ? 0.5 : 1)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { returningTransaction = transaction } label: {
                Label("Delete · returned", icon: "trash")
            }
            .disabled(deletingIDs.contains(transaction.id))
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

    private func refresh() async {
        await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        await transactionStore.loadDebts()
        await rates.load(currencies: Set(currencies), reportingCurrency: currency, force: true)
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
