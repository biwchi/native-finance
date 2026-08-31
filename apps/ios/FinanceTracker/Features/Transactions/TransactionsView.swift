import Foundation
import SwiftUI

struct TransactionsView: View {
    var body: some View {
        NavigationStack {
            TransactionListView()
                .accountSelectorToolbar()
        }
    }
}

struct TransactionListView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @State private var editingTransaction: FinanceTransaction?

    var recentLimit: Int? = nil

    var body: some View {
        List {
            switch transactionStore.state {
            case .idle, .loading:
                ProgressView("Loading transactions")
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

            case .loaded:
                if transactionStore.transactions.isEmpty {
                    ContentUnavailableView(
                        "No transactions yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text(emptyDescription)
                    )
                    .listRowBackground(Color.clear)
                } else if let recentLimit {
                    Section("Recent transactions") {
                        ForEach(transactionStore.transactions.prefix(recentLimit)) { transaction in
                            transactionButton(transaction)
                        }
                    }
                } else {
                    ForEach(transactionGroups, id: \.day) { group in
                        Section {
                            ForEach(group.transactions) { transaction in
                                transactionButton(transaction, showsDate: false)
                            }
                        } header: {
                            Text(group.day, format: .dateTime.day().month(.wide).year())
                        }
                    }
                }

            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn’t load transactions", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task { await reload() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await reload() }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(transaction: transaction)
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func transactionButton(_ transaction: FinanceTransaction, showsDate: Bool = true) -> some View {
        Button {
            editingTransaction = transaction
        } label: {
            TransactionRow(transaction: transaction, showsDate: showsDate)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit transaction")
    }

    private var transactionGroups: [(day: Date, transactions: [FinanceTransaction])] {
        let groups = Dictionary(grouping: transactionStore.transactions) {
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
}

struct TransactionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let transaction: FinanceTransaction
    var showsDate = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let category = transaction.category {
                CategoryIcon(category: category, size: 42)
            } else {
                Image(systemName: transaction.kind == .income ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 42, height: 42)
                    .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    details
                    amount(alignment: .leading)
                }
            } else {
                details
                Spacer(minLength: 12)
                amount(alignment: .trailing)
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 8)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + 54
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
    }

    private func amount(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(amountText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(transaction.kind == .income ? Color.green : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(transaction.currency)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        if let description = transaction.description, !description.isEmpty {
            description
        } else {
            transaction.category?.name ?? transaction.kind.title
        }
    }

    private var subtitle: String {
        let date = showsDate
            ? transaction.occurredAt.formatted(.dateTime.month(.abbreviated).day())
            : transaction.occurredAt.formatted(date: .omitted, time: .shortened)

        if transaction.description?.isEmpty == false, let category = transaction.category {
            return "\(category.name) · \(date)"
        }
        return date
    }

    private var amountText: String {
        let value = Decimal(string: transaction.amount)?.formatted(
            .number.precision(.fractionLength(2...4))
        ) ?? transaction.amount
        return "\(transaction.kind == .income ? "+" : "−")\(value)"
    }

    private var accessibilityDescription: String {
        let date = transaction.occurredAt.formatted(date: .abbreviated, time: .shortened)
        return "\(title), \(transaction.kind.title), \(transaction.amount) \(transaction.currency), \(transaction.category?.name ?? "Uncategorized"), \(date)"
    }

    private var iconColor: Color {
        transaction.kind == .income ? .green : .accentColor
    }
}

#Preview {
    TransactionsView()
        .environmentObject(AccountStore())
        .environmentObject(TransactionStore())
}
