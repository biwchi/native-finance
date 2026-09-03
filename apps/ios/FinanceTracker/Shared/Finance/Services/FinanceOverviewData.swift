import SwiftUI

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
