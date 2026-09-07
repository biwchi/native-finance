import Foundation

enum RecurringForecast {
    enum Period: String, CaseIterable, Identifiable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        case year = "Year"

        var id: Self { self }

        var description: String {
            switch self {
            case .day: "Next day"
            case .week: "Next 7 days"
            case .month: "Next 30 days"
            case .year: "Next 12 months"
            }
        }

        func endDate(from date: Date, calendar: Calendar) -> Date? {
            switch self {
            case .day: calendar.date(byAdding: .day, value: 1, to: date)
            case .week: calendar.date(byAdding: .day, value: 7, to: date)
            case .month: calendar.date(byAdding: .day, value: 30, to: date)
            case .year: calendar.date(byAdding: .year, value: 1, to: date)
            }
        }
    }

    enum KindFilter: String, CaseIterable, Identifiable {
        case expenses = "Expenses"
        case income = "Income"
        case all = "All"

        var id: Self { self }
        var amountTitle: String { self == .all ? "Net cash flow" : rawValue }
        var transactionKind: TransactionKind? {
            switch self {
            case .expenses: .expense
            case .income: .income
            case .all: nil
            }
        }

        func includes(_ kind: TransactionKind) -> Bool {
            kind != .debt && (transactionKind == nil || kind == transactionKind)
        }

        func amount(from totals: Totals) -> Decimal {
            switch self {
            case .expenses: totals.expenses
            case .income: totals.income
            case .all: totals.income - totals.expenses
            }
        }
    }

    struct Totals: Equatable {
        var expenses: Decimal = 0
        var income: Decimal = 0
    }

    static func calculate(
        upcoming: [UpcomingTransaction],
        period: Period,
        filter: KindFilter = .all,
        now: Date = .now,
        calendar: Calendar = .current,
        convert: (Decimal, String) -> Decimal?
    ) -> Totals? {
        guard let end = period.endDate(from: now, calendar: calendar) else { return nil }
        var totals = Totals()
        for bill in upcoming where filter.includes(bill.kind) {
            var date = bill.occurredAt
            var count = 0
            var iterations = 0
            while date < end && bill.endAt.map({ date <= $0 }) != false {
                if date >= now { count += 1 }
                iterations += 1
                guard iterations < 10_000,
                      let next = RecurrenceSchedule.nextOccurrence(after: date, bill: bill),
                      next > date else { return nil }
                date = next
            }
            guard count > 0 else { continue }
            guard let amount = Decimal(string: bill.amount), !amount.isNaN, amount >= 0,
                  let converted = convert(amount, bill.currency), !converted.isNaN else { return nil }
            if bill.kind == .expense {
                totals.expenses += converted * Decimal(count)
            } else {
                totals.income += converted * Decimal(count)
            }
        }
        return totals
    }
}
