import SwiftUI

struct BudgetLimitProgress: Identifiable {
    let id: UUID
    let name: String
    let limit: Decimal
    let spent: Decimal

    var remaining: Decimal { limit - spent }
    var progress: Double { limit > 0 ? NSDecimalNumber(decimal: spent / limit).doubleValue : 0 }

    static func pools(budget: MonthlyBudget, transactions: [FinanceTransaction]) -> [BudgetLimitProgress] {
        let assignments = Dictionary(uniqueKeysWithValues: budget.categoryAssignments.map { ($0.categoryId, $0) })
        return budget.groups.sorted { $0.sortOrder < $1.sortOrder }.compactMap { group in
            guard let limit = Decimal(string: group.limit), limit > 0 else { return nil }
            let spent = transactions.reduce(Decimal.zero) { total, transaction in
                guard transaction.kind == .expense, let category = transaction.category,
                      let amount = Decimal(string: transaction.amount) else { return total }
                // A child's explicit allocation takes precedence over its parent's pool.
                let assignment = assignments[category.id] ?? category.parentId.flatMap { assignments[$0] }
                return assignment?.groupId == group.id ? total + amount : total
            }
            return BudgetLimitProgress(id: group.id, name: group.name, limit: limit, spent: spent)
        }
    }

    static func categories(
        budget: MonthlyBudget, transactions: [FinanceTransaction], categories: [TransactionCategory]
    ) -> [BudgetLimitProgress] {
        budget.categoryAssignments.compactMap { assignment in
            guard let raw = assignment.limit, let limit = Decimal(string: raw), limit > 0 else { return nil }
            let category = categories.first { $0.id == assignment.categoryId }
                ?? transactions.compactMap(\.category).first { $0.id == assignment.categoryId }
            return BudgetLimitProgress(id: assignment.categoryId, name: category?.name ?? "Category unavailable",
                                       limit: limit, spent: spending(transactions, categoryIDs: [assignment.categoryId]))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func spending(_ transactions: [FinanceTransaction], categoryIDs: Set<UUID>) -> Decimal {
        transactions.reduce(0) { total, transaction in
            guard transaction.kind == .expense, let category = transaction.category,
                  categoryIDs.contains(category.id) || category.parentId.map(categoryIDs.contains) == true,
                  let amount = Decimal(string: transaction.amount) else { return total }
            // A transaction contributes once even when its parent and child share a pool.
            return total + amount
        }
    }
}
