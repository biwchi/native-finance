import Foundation

enum RecurrenceSchedule {
    static func nextOccurrence(after date: Date, bill: UpcomingTransaction) -> Date? {
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
}
