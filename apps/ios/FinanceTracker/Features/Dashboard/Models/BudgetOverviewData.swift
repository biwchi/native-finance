import Foundation

struct BudgetOverviewData {
    struct Pool: Identifiable {
        let progress: BudgetLimitProgress
        let categories: [BudgetCategorySpending]
        let spendingOutsidePool: [UUID: Decimal]

        var id: UUID { progress.id }
        var iconName: String { categories.compactMap { $0.category?.icon }.first ?? "credit-cards" }
    }

    struct Attention: Identifiable {
        let progress: BudgetLimitProgress
        let isPool: Bool

        var id: String { "\(isPool ? "pool" : "category")-\(progress.id)" }
    }

    let pools: [Pool]
    let standaloneCategories: [BudgetCategorySpending]
    let attention: [Attention]

    init(budget: MonthlyBudget, transactions: [FinanceTransaction], categories: [TransactionCategory]) {
        let progress = BudgetLimitProgress.pools(budget: budget, transactions: transactions)
        let spending = BudgetCategorySpending.calculate(budget: budget, transactions: transactions, categories: categories)
        let assignments = Dictionary(uniqueKeysWithValues: budget.categoryAssignments.map { ($0.categoryId, $0) })
        let poolIDs = Set(progress.map(\.id))

        pools = progress.map { pool in
            let members = spending.filter { assignments[$0.id]?.groupId == pool.id }
            let poolTransactions = BudgetLimitProgress.transactions(inPool: pool.id, budget: budget, from: transactions)
            // Category limits still cover all children, including children explicitly moved to another pool.
            let outside = Dictionary(uniqueKeysWithValues: members.compactMap { category -> (UUID, Decimal)? in
                let contribution = BudgetLimitProgress.transactions(inCategory: category.id, from: poolTransactions)
                    .reduce(Decimal.zero) { $0 + (Decimal(string: $1.amount) ?? 0) }
                let difference = category.spent - contribution
                return difference != 0 ? (category.id, difference) : nil
            })
            return Pool(progress: pool, categories: members, spendingOutsidePool: outside)
        }
        standaloneCategories = spending.filter { category in
            guard let groupID = assignments[category.id]?.groupId else { return true }
            return !poolIDs.contains(groupID)
        }
        // Keep each limit actionable. Summing these would double-count a category and its pool.
        attention = (progress.filter { $0.remaining < 0 }.map { Attention(progress: $0, isPool: true) }
            + spending.compactMap(\.progress).filter { $0.remaining < 0 }.map { Attention(progress: $0, isPool: false) })
            .sorted {
                if $0.progress.remaining != $1.progress.remaining { return $0.progress.remaining < $1.progress.remaining }
                return $0.id < $1.id
            }
    }

    static func monthProgress(month: Date, now: Date = .now, calendar: Calendar = .current) -> Double? {
        guard calendar.isDate(month, equalTo: now, toGranularity: .month),
              let interval = calendar.dateInterval(of: .month, for: now),
              let days = calendar.range(of: .day, in: .month, for: now) else { return nil }
        let elapsed = calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: now)).day ?? 0
        return Double(elapsed) / Double(days.count)
    }
}
