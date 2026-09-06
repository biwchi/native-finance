import Foundation

struct FinanceDateFilter: Equatable {
    enum Preset: String, CaseIterable, Identifiable {
        case day = "Day"
        case week = "Week"
        case biweekly = "Bi-weekly"
        case month = "Month"
        case year = "Year"
        case last7Days = "Last 7 Days"
        case last30Days = "Last 30 Days"
        case allTime = "All Time"
        case custom = "Custom"

        var id: Self { self }
        var canNavigate: Bool {
            switch self {
            case .day, .week, .biweekly, .month, .year: true
            default: false
            }
        }
    }

    var preset: Preset = .month
    var anchor: Date = .now
    var customEnd: Date = .now

    /// Calendar periods use local midnight boundaries. The custom end date is inclusive.
    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        let day = calendar.startOfDay(for: anchor)
        switch preset {
        case .allTime:
            return nil
        case .day:
            return calendar.dateInterval(of: .day, for: day)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: day)
        case .biweekly:
            // Two calendar weeks, starting with the week containing the chosen date.
            let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 14, to: start) ?? start)
        case .month:
            return calendar.dateInterval(of: .month, for: day)
        case .year:
            return calendar.dateInterval(of: .year, for: day)
        case .last7Days, .last30Days:
            let today = calendar.startOfDay(for: now)
            let count = preset == .last7Days ? 7 : 30
            let start = calendar.date(byAdding: .day, value: 1 - count, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            return DateInterval(start: start, end: end)
        case .custom:
            let start = calendar.startOfDay(for: min(anchor, customEnd))
            let last = calendar.startOfDay(for: max(anchor, customEnd))
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: last) ?? last)
        }
    }

    func transactionInterval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        guard let interval = interval(now: now, calendar: calendar) else { return nil }
        var end = interval.end
        // Keep current calendar-period totals consistent with the existing month-to-date summary.
        if preset.canNavigate, now >= interval.start, now < end {
            end = min(end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? end)
        }
        return DateInterval(start: interval.start, end: end)
    }

    func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let interval = transactionInterval(now: now, calendar: calendar) else { return true }
        return date >= interval.start && date < interval.end
    }

    /// Compare completed periods in full, and active calendar periods at the same elapsed day.
    /// Custom and rolling ranges compare with the immediately preceding range of calendar days.
    func comparisonInterval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        guard let full = interval(now: now, calendar: calendar),
              let selected = transactionInterval(now: now, calendar: calendar),
              let previous = shifted(by: -1, now: now, calendar: calendar)
                .interval(now: now, calendar: calendar) else { return nil }
        guard selected.end < full.end else { return previous }
        let days = calendar.dateComponents([.day], from: selected.start, to: selected.end).day ?? 0
        let end = calendar.date(byAdding: .day, value: days, to: previous.start) ?? previous.end
        return DateInterval(start: previous.start, end: min(end, previous.end))
    }

    func shifted(by value: Int, now: Date = .now, calendar: Calendar = .current) -> Self {
        guard preset != .allTime else { return self }
        if !preset.canNavigate {
            guard let interval = interval(now: now, calendar: calendar) else { return self }
            let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
            let start = calendar.date(byAdding: .day, value: days * value, to: interval.start) ?? interval.start
            let end = calendar.date(byAdding: .day, value: days - 1, to: start) ?? start
            return Self(preset: .custom, anchor: start, customEnd: end)
        }
        let component: Calendar.Component = preset == .month ? .month : preset == .year ? .year : .day
        let step = preset == .week ? 7 : preset == .biweekly ? 14 : 1
        // Shift from the period start so Jan 31 → Feb → Mar never drifts or skips a month.
        let start = interval(calendar: calendar)?.start ?? anchor
        var result = self
        result.anchor = calendar.date(byAdding: component, value: value * step, to: start) ?? start
        return result
    }

    func label(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch preset {
        case .day:
            return dayLabel(anchor, now: now, calendar: calendar, locale: locale)
        case .month:
            return formatted(anchor, template: sameYear(anchor, now, calendar) ? "LLLL" : "LLLL y", calendar: calendar, locale: locale)
        case .year:
            return formatted(anchor, template: "y", calendar: calendar, locale: locale)
        case .last7Days, .last30Days, .allTime:
            return preset.rawValue
        case .week, .biweekly, .custom:
            guard let interval = interval(now: now, calendar: calendar),
                  let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return preset.rawValue }
            if calendar.isDate(interval.start, inSameDayAs: last) {
                return dayLabel(interval.start, now: now, calendar: calendar, locale: locale)
            }
            let formatter = DateIntervalFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateTemplate = sameYear(interval.start, now, calendar) && sameYear(last, now, calendar)
                ? "MMMd" : "yMMMd"
            return formatter.string(from: interval.start, to: last)
        }
    }

    private func dayLabel(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return formatted(date, template: sameYear(date, now, calendar) ? "dMMMM" : "dMMMM y", calendar: calendar, locale: locale)
    }

    private func sameYear(_ first: Date, _ second: Date, _ calendar: Calendar) -> Bool {
        calendar.isDate(first, equalTo: second, toGranularity: .year)
    }

    private func formatted(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
