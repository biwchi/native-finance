import Foundation
import SwiftUI

struct TransactionListView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @State private var editingTransaction: FinanceTransaction?
    @State private var presentedAlert: TransactionListAlert?
    @State private var deletingTransactionID: UUID?
    var recentLimit: Int?

    var body: some View {
        AppList {
            if transactionStore.transactions(for: accountStore.selectedAccountID).isEmpty {
                ContentUnavailableView(
                    "No transactions yet",
                    iconName: "list",
                    description: Text(emptyDescription)
                )
                .listRowBackground(Color.clear)
            } else if let recentLimit {
                AppSection("Recent transactions") {
                    ForEach(transactionStore.transactions(for: accountStore.selectedAccountID).prefix(recentLimit)) { transaction in
                        transactionButton(transaction)
                    }
                }
            } else {
                ForEach(transactionGroups, id: \.day) { group in
                    AppSection {
                        ForEach(group.transactions) { transaction in
                            transactionButton(transaction)
                        }
                    } header: {
                        Text(group.day, format: .dateTime.day().month(.wide).year())
                    }
                }
            }

        }
        .animateListChanges(value: transactionStore.allTransactions.map(\.id))
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(4))
        .environment(\.defaultMinListRowHeight, 0)
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
                Text(transaction.kind == .debt
                     ? "This records the money as returned and restores the original account’s balance."
                     : transaction.recurrence == nil
                     ? "This can't be undone."
                     : "This is a recurring transaction. What would you like to delete?")
            case let .error(message):
                Text(message)
            }
        }
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
        .circleSwipeActions(isEnabled: deletingTransactionID == nil) {
            CircleSwipeAction(title: "Delete", icon: "trash") {
                presentedAlert = .confirmDeletion(transaction)
            }
        }
    }

    private var transactionGroups: [(day: Date, transactions: [FinanceTransaction])] {
        let groups = Dictionary(grouping: transactionStore.transactions(for: accountStore.selectedAccountID)) {
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
