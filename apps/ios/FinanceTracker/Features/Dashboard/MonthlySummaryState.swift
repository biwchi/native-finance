import Foundation

enum BudgetStatus: Equatable {
    case onTrack
    case watchSpending
    case nearLimit
    case overLimit

    var displayText: String {
        switch self {
        case .onTrack: String(localized: "On track")
        case .watchSpending: String(localized: "Watch spending")
        case .nearLimit: String(localized: "Near limit")
        case .overLimit: String(localized: "Over limit")
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .watchSpending:
            String(localized: "Watch spending. Spending is ahead of this month's pace.")
        default: displayText
        }
    }
}

struct MonthlySummaryState {
    let monthlyBudget: Decimal
    let amountSpent: Decimal
    let remaining: Decimal
    let budgetProgress: Double
    let monthProgress: Double
    let daysRemaining: Int
    let status: BudgetStatus
    let currentDate: Date
    let startOfMonth: Date
    /// Exclusive upper boundary: the start of the following month.
    let endOfMonth: Date
    let currency: String
    let locale: Locale
    let calendar: Calendar

    /// The dashboard hides the summary when no usable monthly limit is configured.
    /// Negative spending is treated as zero here, without altering transaction totals.
    init?(
        monthlyBudget: Decimal?,
        amountSpent: Decimal,
        currentDate: Date,
        startOfMonth: Date,
        endOfMonth: Date,
        currency: String,
        locale: Locale,
        calendar: Calendar = .current
    ) {
        guard let monthlyBudget, !monthlyBudget.isNaN, monthlyBudget > 0,
              !amountSpent.isNaN, endOfMonth > startOfMonth else { return nil }

        let spent = max(0, amountSpent)
        let progress = NSDecimalNumber(decimal: spent).doubleValue
            / NSDecimalNumber(decimal: monthlyBudget).doubleValue
        let elapsed = min(max(currentDate.timeIntervalSince(startOfMonth)
            / endOfMonth.timeIntervalSince(startOfMonth), 0), 1)

        self.monthlyBudget = monthlyBudget
        self.amountSpent = spent
        remaining = monthlyBudget - spent
        budgetProgress = progress
        monthProgress = elapsed
        self.currentDate = currentDate
        self.startOfMonth = startOfMonth
        self.endOfMonth = endOfMonth
        self.currency = currency.uppercased()
        self.locale = locale
        self.calendar = calendar

        // Count whole calendar days after today, not 24-hour intervals (DST safe).
        let tomorrow = calendar.date(byAdding: .day, value: 1,
                                     to: calendar.startOfDay(for: currentDate)) ?? endOfMonth
        daysRemaining = max(0, calendar.dateComponents(
            [.day], from: min(max(tomorrow, startOfMonth), endOfMonth), to: endOfMonth
        ).day ?? 0)

        if spent > monthlyBudget {
            status = .overLimit
        } else if progress >= 0.85 {
            status = .nearLimit
        } else if progress > elapsed + 0.10 {
            status = .watchSpending
        } else {
            status = .onTrack
        }
    }

    var isCurrentMonth: Bool { currentDate >= startOfMonth && currentDate < endOfMonth }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.component(.year, from: startOfMonth) == calendar.component(.year, from: currentDate)
                ? "LLLL" : "LLL yyyy"
        )
        return formatter.string(from: startOfMonth)
    }

    var amountText: String { money(abs(remaining)) }

    var amountSuffix: String {
        status == .overLimit ? String(localized: "over") : String(localized: "left")
    }

    var spendingText: String {
        String(localized: "\(money(amountSpent)) of \(money(monthlyBudget)) spent")
    }

    var timeRemainingText: String {
        if currentDate >= endOfMonth { return String(localized: "Month ended") }
        if currentDate < startOfMonth { return String(localized: "Upcoming month") }
        if daysRemaining == 0 { return String(localized: "Last day") }
        if daysRemaining == 1 { return String(localized: "1 day left") }
        return String(localized: "\(daysRemaining) days left")
    }

    var accessibilityLabel: String {
        let amount = money(abs(remaining), spoken: true)
        let balance = status == .overLimit
            ? String(localized: "\(amount) over budget")
            : String(localized: "\(amount) remaining")
        let spending = String(localized: "\(money(amountSpent, spoken: true)) spent of \(money(monthlyBudget, spoken: true))")
        return String(localized: "\(monthTitle) budget. \(balance). \(spending). \(timeRemainingText). \(status.accessibilityDescription)")
    }

    private func money(_ value: Decimal, spoken: Bool = false) -> String {
        var style = Decimal.FormatStyle.Currency(code: currency)
            .presentation(spoken ? .fullName : .narrow)
            .locale(locale)
        var source = value
        var whole = Decimal()
        NSDecimalRound(&whole, &source, 0, .plain)
        // Keep ISO currency precision for fractional values, including JPY and KWD.
        if whole == value { style = style.precision(.fractionLength(0)) }
        return value.formatted(style)
    }
}
