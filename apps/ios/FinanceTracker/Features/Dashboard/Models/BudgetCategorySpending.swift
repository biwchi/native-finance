import Foundation

struct BudgetCategorySpending: Identifiable {
    let id: UUID
    let name: String
    let spent: Decimal
    let limit: Decimal?
    let poolName: String?

    var progress: BudgetLimitProgress? {
        guard let limit, limit > 0 else { return nil }
        return BudgetLimitProgress(id: id, name: name, limit: limit, spent: spent)
    }

    static func calculate(
        budget: MonthlyBudget, transactions: [FinanceTransaction], categories: [TransactionCategory]
    ) -> [BudgetCategorySpending] {
        budget.categoryAssignments.map { assignment in
            let category = categories.first { $0.id == assignment.categoryId }
                ?? transactions.compactMap(\.category).first { $0.id == assignment.categoryId }
            let spent = BudgetLimitProgress.transactions(inCategory: assignment.categoryId, from: transactions)
                .reduce(Decimal.zero) { $0 + (Decimal(string: $1.amount) ?? 0) }
            return BudgetCategorySpending(
                id: assignment.categoryId, name: category?.name ?? "Category unavailable",
                spent: spent, limit: assignment.limit.flatMap { Decimal(string: $0) },
                poolName: budget.groups.first { $0.id == assignment.groupId }?.name
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
