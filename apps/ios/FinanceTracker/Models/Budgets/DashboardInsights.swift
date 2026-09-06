import Foundation

struct DashboardInsights: Equatable {
    let income: Decimal
    let spent: Decimal
    let previousSpent: Decimal
    let net: Decimal
    let monthlyLimit: Decimal?

    var remaining: Decimal? {
        monthlyLimit.map { $0 - spent }
    }

    var budgetProgress: Decimal? {
        guard let monthlyLimit, monthlyLimit > 0 else { return nil }
        return spent / monthlyLimit
    }

    var paceDifference: Decimal {
        previousSpent - spent
    }

    var comparisonPercent: Decimal? {
        guard previousSpent > 0 else { return nil }
        return ((spent - previousSpent) / previousSpent) * 100
    }

    var hasBudget: Bool {
        guard let monthlyLimit else { return false }
        return !monthlyLimit.isNaN && monthlyLimit > 0
    }

    static func calculate(
        transactions: [FinanceTransaction],
        filter: FinanceDateFilter,
        now: Date = .now,
        calendar: Calendar = .current,
        monthlyLimit: Decimal? = nil
    ) -> DashboardInsights {
        let selected = filter.transactionInterval(now: now, calendar: calendar)
        let previous = filter.comparisonInterval(now: now, calendar: calendar)
        var income = Decimal.zero
        var spent = Decimal.zero
        var previousSpent = Decimal.zero

        for transaction in transactions {
            guard let amount = Decimal(string: transaction.amount), !amount.isNaN else { continue }
            if selected.map({ transaction.occurredAt >= $0.start && transaction.occurredAt < $0.end }) ?? true {
                if transaction.kind == .income {
                    income += amount
                } else if transaction.kind == .expense {
                    spent += amount
                }
            }
            if transaction.kind == .expense, let previous,
               transaction.occurredAt >= previous.start, transaction.occurredAt < previous.end {
                previousSpent += amount
            }
        }

        return DashboardInsights(
            income: income, spent: spent, previousSpent: previousSpent, net: income - spent,
            monthlyLimit: filter.preset == .month ? monthlyLimit : nil
        )
    }

    static func calculate(
        transactions: [FinanceTransaction],
        month: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        monthlyLimit: Decimal?
    ) -> DashboardInsights {
        calculate(transactions: transactions, filter: FinanceDateFilter(anchor: month),
                  now: now, calendar: calendar, monthlyLimit: monthlyLimit)
    }
}
