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
                                transactionButton(transaction)
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

    private func transactionButton(_ transaction: FinanceTransaction) -> some View {
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
    let account: Account?

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
                    amount
                }
            } else {
                details
                Spacer(minLength: 12)
                amount
                    .layoutPriority(1)
            }
        }
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

            accountLabel
        }
    }

    private var accountLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: account?.icon ?? "creditcard")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(account?.iconColor.color ?? Color.secondary)
                .accessibilityHidden(true)

            Text(account?.name ?? "Unknown account")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
    }

    private var amount: some View {
        Text(amountText)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(transaction.kind == .income ? Color.green : .primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var title: String {
        transaction.category?.name ?? "Uncategorized"
    }

    private var amountText: String {
        let value = Decimal(string: transaction.amount).flatMap(formattedAmount) ?? transaction.amount
        let sign = transaction.kind == .income ? "+" : "-"
        return "\(sign) \(value) \(transaction.currency)"
    }

    private func formattedAmount(_ amount: Decimal) -> String? {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        return formatter.string(from: amount as NSDecimalNumber)
    }

    private var accessibilityDescription: String {
        let date = transaction.occurredAt.formatted(date: .abbreviated, time: .shortened)
        return "\(title), \(account?.name ?? "Unknown account"), \(amountText), \(date)"
    }

    private var iconColor: Color {
        transaction.kind == .income ? .green : .accentColor
    }
}

#Preview("Transaction row", traits: .sizeThatFitsLayout) {
    let timestamp = Date.now
    let category = TransactionCategory(
        id: UUID(),
        systemKey: "expense.food-drink",
        name: "Food & Drink",
        kind: .expense,
        isSystem: true,
        examples: nil,
        sortOrder: 10,
        createdAt: timestamp,
        updatedAt: timestamp
    )
    let transaction = FinanceTransaction(
        id: UUID(),
        accountId: TransactionListPreviewData.account.id,
        kind: .expense,
        amount: "6.50",
        currency: "USD",
        category: category,
        description: "Morning coffee",
        note: nil,
        occurredAt: timestamp,
        createdAt: timestamp,
        updatedAt: timestamp
    )

    ZStack {
        Color(red: 0.06, green: 0.07, blue: 0.09)

        TransactionRow(transaction: transaction, account: TransactionListPreviewData.account)
            .padding(16)
            .background(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .padding(20)
    }
    .frame(width: 390, height: 136)
    .preferredColorScheme(.dark)
}

#Preview("Transaction list") {
    TransactionsView()
        .environmentObject(AccountStore())
        .environmentObject(
            TransactionStore.preview(
                transactions: TransactionListPreviewData.transactions
            )
        )
        .preferredColorScheme(.dark)
}

private enum TransactionListPreviewData {
    static let accountID = UUID()
    static let now = Date.now
    static let account = Account(
        id: accountID,
        name: "Everyday card",
        type: .checking,
        currency: "USD",
        icon: "creditcard.fill",
        iconColor: .blue,
        createdAt: "",
        updatedAt: ""
    )

    static let food = category(
        systemKey: "expense.food-drink",
        name: "Food & Drink",
        kind: .expense
    )
    static let groceries = category(
        systemKey: "expense.groceries",
        name: "Groceries",
        kind: .expense
    )
    static let transport = category(
        systemKey: "expense.transport",
        name: "Transport",
        kind: .expense
    )
    static let salary = category(
        systemKey: "income.salary",
        name: "Salary",
        kind: .income
    )

    static let transactions = [
        transaction(
            kind: .income,
            amount: "3200.00",
            category: salary,
            description: "Monthly salary",
            occurredAt: now
        ),
        transaction(
            kind: .expense,
            amount: "6.50",
            category: food,
            description: "Morning coffee",
            occurredAt: now.addingTimeInterval(-2 * 60 * 60)
        ),
        transaction(
            kind: .expense,
            amount: "84.20",
            category: groceries,
            description: "Weekly groceries",
            occurredAt: now.addingTimeInterval(-28 * 60 * 60)
        ),
        transaction(
            kind: .expense,
            amount: "18.75",
            category: transport,
            description: "Taxi home",
            occurredAt: now.addingTimeInterval(-32 * 60 * 60)
        ),
    ]

    private static func category(
        systemKey: String,
        name: String,
        kind: TransactionKind
    ) -> TransactionCategory {
        TransactionCategory(
            id: UUID(),
            systemKey: systemKey,
            name: name,
            kind: kind,
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
        category: TransactionCategory,
        description: String,
        occurredAt: Date
    ) -> FinanceTransaction {
        FinanceTransaction(
            id: UUID(),
            accountId: accountID,
            kind: kind,
            amount: amount,
            currency: "USD",
            category: category,
            description: description,
            note: nil,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            updatedAt: occurredAt
        )
    }
}
