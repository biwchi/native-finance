import Foundation
import SwiftUI

struct TransactionsView: View {
    var body: some View {
        TransactionListView()
            .navigationTitle("Transactions")
            .accountSelectorToolbar()
    }
}

struct TransactionListView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @State private var editingTransaction: FinanceTransaction?
    @State private var presentedAlert: TransactionListAlert?
    @State private var deletingTransactionID: UUID?

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
                        iconName: "list",
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

private enum TransactionListAlert: Identifiable {
    case confirmDeletion(FinanceTransaction)
    case error(String)

    var id: String {
        switch self {
        case let .confirmDeletion(transaction): "delete-\(transaction.id.uuidString)"
        case let .error(message): "error-\(message)"
        }
    }

    var title: String {
        switch self {
        case let .confirmDeletion(transaction):
            transaction.recurrence == nil ? "Delete transaction?" : "Choose an action"
        case .error: "Couldn't delete transaction"
        }
    }
}

struct TransactionRow: View {
    enum Style {
        case transaction
        case upcoming
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let transaction: any EditableTransaction
    let account: Account?
    var titleOverride: String? = nil
    var recurrenceDetails: String? = nil
    var style: Style = .transaction

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            transactionIcon

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

    private var transactionIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let category = transaction.category {
                    CategoryIcon(category: category, size: 42)
                } else {
                    AppIcon(transaction.kind == .income ? "arrow-down-left" : "arrow-up-right", size: 18)
                        .foregroundStyle(iconColor)
                        .frame(width: 42, height: 42)
                        .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if style == .transaction, transaction.recurrence != nil {
                AppIcon("repeat", size: 8)
                    .foregroundStyle(Color.primary)
                    .frame(width: 16, height: 16)
                    .background(.regularMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    }
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 45, height: 45, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            if style == .transaction {
                accountLabel
            }

            if let recurrenceDetails {
                Text(recurrenceDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accountLabel: some View {
        HStack(spacing: 5) {
            AppIcon(account?.icon ?? "credit-card", size: 11)
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
        titleOverride ?? transaction.category?.name ?? "Uncategorized"
    }

    private var amountText: String {
        transaction.formattedAmount(showExpenseSign: style == .transaction)
    }

    private var accessibilityDescription: String {
        let date = transaction.occurredAt.formatted(date: .abbreviated, time: .shortened)
        let recurrence = transaction.recurrence.map {
            ", recurring \($0.frequency.title.lowercased())"
        } ?? ""
        let accountDetails = style == .transaction ? ", \(account?.name ?? "Unknown account")" : ""
        return "\(title)\(accountDetails), \(amountText), \(date)\(recurrence)"
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
        note: nil,
        occurredAt: timestamp,
        createdAt: timestamp,
        updatedAt: timestamp,
        recurrence: TransactionRecurrence(
            id: UUID(),
            frequency: .daily,
            endAt: nil
        )
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
        .environmentObject(BudgetStore.preview())
        .environmentObject(ExchangeRateStore())
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
        icon: "credit-card",
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
            occurredAt: now,
            recurrence: TransactionRecurrence(
                id: UUID(),
                frequency: .monthly,
                endAt: nil
            )
        ),
        transaction(
            kind: .expense,
            amount: "6.50",
            category: food,
            occurredAt: now.addingTimeInterval(-2 * 60 * 60)
        ),
        transaction(
            kind: .expense,
            amount: "84.20",
            category: groceries,
            occurredAt: now.addingTimeInterval(-28 * 60 * 60)
        ),
        transaction(
            kind: .expense,
            amount: "18.75",
            category: transport,
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
        occurredAt: Date,
        recurrence: TransactionRecurrence? = nil
    ) -> FinanceTransaction {
        FinanceTransaction(
            id: UUID(),
            accountId: accountID,
            kind: kind,
            amount: amount,
            currency: "USD",
            category: category,
            note: nil,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            updatedAt: occurredAt,
            recurrence: recurrence
        )
    }
}
