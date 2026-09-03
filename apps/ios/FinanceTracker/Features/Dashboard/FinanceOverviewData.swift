import Foundation

extension FinanceTransaction {
    func replacingAmount(_ amount: String, currency: String) -> FinanceTransaction {
        FinanceTransaction(
            id: id,
            accountId: accountId,
            kind: kind,
            amount: amount,
            currency: currency,
            category: category,
            merchant: merchant,
            payee: payee,
            note: note,
            occurredAt: occurredAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            recurrence: recurrence
        )
    }
}

extension MonthlyBudget {
    @MainActor
    func converted(to currency: String, using rates: ExchangeRateStore) -> MonthlyBudget? {
        guard self.currency.caseInsensitiveCompare(currency) != .orderedSame else {
            return self
        }

        func convert(_ amount: String) -> String? {
            guard let decimal = Decimal(
                string: amount,
                locale: Locale(identifier: "en_US_POSIX")
            ), let converted = rates.convert(
                decimal,
                from: self.currency,
                to: currency
            ) else {
                return nil
            }
            var value = converted
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 4, .bankers)
            return NSDecimalNumber(decimal: rounded).stringValue
        }

        let convertedLimit: String?
        if let monthlyLimit {
            guard let value = convert(monthlyLimit) else { return nil }
            convertedLimit = value
        } else {
            convertedLimit = nil
        }

        let convertedGroups = groups.compactMap { group -> BudgetGroup? in
            guard let limit = convert(group.limit) else { return nil }
            return BudgetGroup(
                id: group.id,
                name: group.name,
                limit: limit,
                sortOrder: group.sortOrder
            )
        }
        guard convertedGroups.count == groups.count else { return nil }

        let convertedAssignments = categoryAssignments.compactMap {
            assignment -> BudgetCategoryAssignment? in
            guard let currentLimit = assignment.limit else {
                return BudgetCategoryAssignment(
                    categoryId: assignment.categoryId,
                    groupId: assignment.groupId,
                    limit: nil
                )
            }
            guard let limit = convert(currentLimit) else { return nil }
            return BudgetCategoryAssignment(
                categoryId: assignment.categoryId,
                groupId: assignment.groupId,
                limit: limit
            )
        }
        guard convertedAssignments.count == categoryAssignments.count else { return nil }

        return MonthlyBudget(
            id: id,
            accountId: accountId,
            month: month,
            currency: currency,
            monthlyLimit: convertedLimit,
            groups: convertedGroups,
            categoryAssignments: convertedAssignments,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}


/// Shared month and search rules keep the visible ledger and its totals aligned.
enum FinanceOverviewData {
    static func transactions(
        _ transactions: [FinanceTransaction], in month: Date,
        now: Date = .now, calendar: Calendar = .current
    ) -> [FinanceTransaction] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let end = spendingEnd(month: month, now: now, calendar: calendar)
        return transactions.filter { $0.occurredAt >= interval.start && $0.occurredAt < end }
            .sorted { $0.occurredAt == $1.occurredAt ? $0.createdAt > $1.createdAt : $0.occurredAt > $1.occurredAt }
    }

    static func spendingEnd(month: Date, now: Date, calendar: Calendar) -> Date {
        let end = calendar.dateInterval(of: .month, for: month)?.end ?? month
        guard calendar.isDate(month, equalTo: now, toGranularity: .month) else { return end }
        return min(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? end, end)
    }

    static func matches(_ transaction: FinanceTransaction, query: String, accounts: [Account]) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [transaction.merchant, transaction.payee, transaction.note,
                transaction.category?.name, transaction.category == nil ? "Uncategorized" : nil,
                transaction.amount, transaction.formattedAmount(),
                accounts.first { $0.id == transaction.accountId }?.name]
            .compactMap { $0 }
            .contains { $0.localizedStandardContains(query) }
    }

    @MainActor
    static func converted(
        _ transactions: [FinanceTransaction], to currency: String, using rates: ExchangeRateStore
    ) -> [FinanceTransaction]? {
        var result: [FinanceTransaction] = []
        for transaction in transactions {
            guard let amount = Decimal(string: transaction.amount), !amount.isNaN,
                  let value = rates.convert(amount, from: transaction.currency, to: currency) else { return nil }
            result.append(transaction.replacingAmount(NSDecimalNumber(decimal: value).stringValue, currency: currency))
        }
        return result
    }
}

struct PlannedBillsSummary {
    let planned: Decimal
    let afterBills: Decimal
    let dailyAmount: Decimal?
    let dailyRange: ClosedRange<Date>?

    /// Upcoming contains one next occurrence per schedule. Expand repeats through the
    /// selected month and skip occurrences already counted by the ledger.
    static func calculate(
        summary: MonthlySummaryState,
        transactions: [FinanceTransaction],
        upcoming: [UpcomingTransaction],
        convert: (Decimal, String) -> Decimal?
    ) -> PlannedBillsSummary? {
        let now = summary.currentDate
        let calendar = summary.calendar
        let end = summary.endOfMonth
        let start = summary.startOfMonth
        let spentThrough = FinanceOverviewData.spendingEnd(month: start, now: now, calendar: calendar)
        var planned = Decimal.zero

        // Include future one-time entries as well as any recorded future repeats.
        for transaction in transactions where transaction.kind == .expense
            && transaction.occurredAt >= max(start, spentThrough) && transaction.occurredAt < end {
            guard let amount = Decimal(string: transaction.amount), !amount.isNaN,
                  let value = convert(amount, transaction.currency) else { return nil }
            planned += value
        }

        for bill in upcoming where bill.kind == .expense && bill.occurredAt < end {
            var date = bill.occurredAt
            var count = 0
            var iterations = 0
            while date < end && (bill.endAt == nil || date <= bill.endAt!) {
                let isRecorded = transactions.contains {
                    $0.recurrence?.id == bill.id && abs($0.occurredAt.timeIntervalSince(date)) < 0.001
                }
                if date > now && date >= start && !isRecorded { count += 1 }
                iterations += 1
                guard iterations < 10_000,
                      let next = nextOccurrence(after: date, bill: bill), next > date else { return nil }
                date = next
            }
            if count > 0 {
                guard let amount = Decimal(string: bill.amount), !amount.isNaN,
                      let value = convert(amount, bill.currency) else { return nil }
                planned += value * Decimal(count)
            }
        }

        let afterBills = summary.remaining - planned
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? end
        let dailyStart = max(start, tomorrow)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        let days = summary.daysRemaining
        let range = days > 0 && dailyStart <= lastDay ? dailyStart...lastDay : nil
        var daily = days > 0 ? max(0, afterBills) / Decimal(days) : Decimal.zero
        var rounded = Decimal()
        // Never round a daily allowance up past the available budget.
        NSDecimalRound(&rounded, &daily, 2, .down)
        return PlannedBillsSummary(planned: planned, afterBills: afterBills,
                                   dailyAmount: range == nil ? nil : rounded, dailyRange: range)
    }

    private static func nextOccurrence(after date: Date, bill: UpcomingTransaction) -> Date? {
        // Recurring schedules use UTC in the API, even across local daylight-saving changes.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        switch bill.frequency {
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly, .yearly:
            let anchor = calendar.dateComponents([.month, .day, .hour, .minute, .second, .nanosecond],
                                                  from: bill.startAt ?? bill.occurredAt)
            var target = calendar.dateComponents([.year, .month], from: date)
            if bill.frequency == .monthly {
                guard let month = calendar.date(from: target),
                      let next = calendar.date(byAdding: .month, value: 1, to: month) else { return nil }
                target = calendar.dateComponents([.year, .month], from: next)
            } else {
                target.year = (target.year ?? 0) + 1
                target.month = anchor.month
            }
            guard let month = calendar.date(from: target),
                  let days = calendar.range(of: .day, in: .month, for: month) else { return nil }
            target.day = min(anchor.day ?? 1, days.count)
            target.hour = anchor.hour
            target.minute = anchor.minute
            target.second = anchor.second
            target.nanosecond = anchor.nanosecond
            return calendar.date(from: target)
        }
    }
}

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
