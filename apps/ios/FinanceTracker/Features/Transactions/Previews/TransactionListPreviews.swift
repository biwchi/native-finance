import SwiftUI

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
        AppColor.groupedBackground

        TransactionRow(transaction: transaction, account: TransactionListPreviewData.account)
            .padding(AppSpacing.large)
            .background(
                in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
            )
            .padding(AppSpacing.extraLarge)
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
