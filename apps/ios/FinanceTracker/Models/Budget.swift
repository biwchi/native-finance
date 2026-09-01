import Foundation

struct MonthlyBudget: Codable, Identifiable, Equatable {
    let id: UUID
    let accountId: UUID?
    let month: String
    let currency: String
    let monthlyLimit: String?
    let groups: [BudgetGroup]
    let categoryAssignments: [BudgetCategoryAssignment]
    let createdAt: Date
    let updatedAt: Date
}

struct BudgetGroup: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let limit: String
    let sortOrder: Int
}

struct BudgetCategoryAssignment: Codable, Equatable {
    let categoryId: UUID
    let groupId: UUID?
    let limit: String?
}

struct MonthlyBudgetRequest: Encodable {
    let month: String
    let accountId: UUID?
    let currency: String
    let monthlyLimit: String?
    let groups: [BudgetGroupRequest]
    let categoryAssignments: [BudgetCategoryAssignmentRequest]
}

struct BudgetGroupRequest: Encodable {
    let id: UUID
    let name: String
    let limit: String
}

struct BudgetCategoryAssignmentRequest: Encodable {
    let categoryId: UUID
    let groupId: UUID?
    let limit: String?
}

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

    static func calculate(
        transactions: [FinanceTransaction],
        month: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        monthlyLimit: Decimal?
    ) -> DashboardInsights {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let isCurrentMonth = calendar.isDate(monthStart, equalTo: currentMonth, toGranularity: .month)

        let end = isCurrentMonth
            ? min(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? nextMonth, nextMonth)
            : nextMonth
        let elapsedDays = max(1, calendar.dateComponents([.day], from: monthStart, to: end).day ?? 1)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let previousNextMonth = monthStart
        let previousEnd = min(
            calendar.date(byAdding: .day, value: elapsedDays, to: previousStart) ?? previousNextMonth,
            previousNextMonth
        )

        var income = Decimal.zero
        var spent = Decimal.zero
        var previousSpent = Decimal.zero

        for transaction in transactions {
            guard let amount = Decimal(string: transaction.amount) else { continue }

            if transaction.occurredAt >= monthStart, transaction.occurredAt < end {
                if transaction.kind == .income {
                    income += amount
                } else {
                    spent += amount
                }
            } else if transaction.kind == .expense,
                      transaction.occurredAt >= previousStart,
                      transaction.occurredAt < previousEnd {
                previousSpent += amount
            }
        }

        return DashboardInsights(
            income: income,
            spent: spent,
            previousSpent: previousSpent,
            net: income - spent,
            monthlyLimit: monthlyLimit
        )
    }
}

enum BudgetMonth {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
