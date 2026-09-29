import Foundation

enum RecurrenceSchedule {
    static func nextOccurrence(after date: Date, bill: UpcomingTransaction) -> Date? {
        if let identifier = bill.timeZone {
            guard let timeZone = TimeZone(identifier: identifier) else { return nil }
            return nextLocalOccurrence(after: date, bill: bill, timeZone: timeZone)
        }
        // Match the API's UTC schedule, preserving the original month-end or leap-day anchor.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        switch bill.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly, .yearly:
            let anchor = calendar.dateComponents(
                [.month, .day, .hour, .minute, .second, .nanosecond],
                from: bill.startAt ?? bill.occurredAt
            )
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

    private static func nextLocalOccurrence(after date: Date, bill: UpcomingTransaction, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = bill.startAt ?? bill.occurredAt
        let anchor = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        let current = calendar.dateComponents([.year, .month], from: date)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
        let elapsed: Int
        switch bill.frequency {
        case .daily: elapsed = days
        case .weekly: elapsed = days / 7
        case .monthly: elapsed = ((current.year ?? 0) - (anchor.year ?? 0)) * 12 + (current.month ?? 0) - (anchor.month ?? 0)
        case .yearly: elapsed = (current.year ?? 0) - (anchor.year ?? 0)
        }
        guard elapsed <= 10_000 else { return nil }
        for count in max(1, elapsed)...10_000 {
            let targetDay: Date?
            switch bill.frequency {
            case .daily, .weekly:
                targetDay = calendar.date(byAdding: .day, value: count * (bill.frequency == .weekly ? 7 : 1), to: calendar.startOfDay(for: start))
            case .monthly, .yearly:
                var first = DateComponents(year: anchor.year, month: anchor.month, day: 1)
                if bill.frequency == .monthly { first.month = (anchor.month ?? 1) + count }
                else { first.year = (anchor.year ?? 0) + count }
                guard let month = calendar.date(from: first), let range = calendar.range(of: .day, in: .month, for: month) else { return nil }
                targetDay = calendar.date(byAdding: .day, value: min(anchor.day ?? 1, range.count) - 1, to: month)
            }
            guard let targetDay,
                  let candidate = calendar.nextDate(after: targetDay.addingTimeInterval(-1),
                    matching: DateComponents(hour: anchor.hour, minute: anchor.minute, second: anchor.second),
                    matchingPolicy: .nextTimePreservingSmallerComponents, repeatedTimePolicy: .first) else { return nil }
            if candidate > date { return candidate }
        }
        return nil
    }
}
