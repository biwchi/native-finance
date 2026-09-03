import SwiftUI

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
