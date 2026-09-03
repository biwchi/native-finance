import SwiftUI

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
        icon: "credit-card",
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
        icon: "cutlery",
        color: .orange
    )
    static let housing = category(
        systemKey: "expense.housing",
        name: "Housing",
        icon: "home-simple",
        color: .blue
    )
    static let shopping = category(
        systemKey: "expense.shopping",
        name: "Shopping",
        icon: "shopping-bag",
        color: .purple
    )
    static let salary = TransactionCategory(
        id: UUID(),
        systemKey: "income.salary",
        name: "Salary",
        kind: .income,
        icon: "cash",
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
