import Foundation

protocol EditableTransaction {
    var debt: Debt? { get }
    var debtId: UUID? { get }
    var accountId: UUID { get }
    var kind: TransactionKind { get }
    var amount: String { get }
    var currency: String { get }
    var category: TransactionCategory? { get }
    var counterparty: String? { get }
    var note: String? { get }
    var occurredAt: Date { get }
    var recurrence: TransactionRecurrence? { get }
}

extension EditableTransaction {
    var counterparty: String? { nil }
    var debt: Debt? { nil }
    var debtId: UUID? { debt?.id }

    func formattedAmount(showExpenseSign: Bool = true) -> String {
        guard let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else {
            return "Unavailable"
        }
        let magnitude = abs(value)
        return MoneyFormatter.format(
            kind != .income && showExpenseSign ? -magnitude : magnitude,
            currency: currency,
            showPositiveSign: kind == .income
        )
    }
}

struct TransactionAmountDisplay {
    let primary: String
    let original: String?

    init(_ transaction: any EditableTransaction, currency: String?, rates: ExchangeRateSnapshot?, showExpenseSign: Bool = true) {
        let saved = transaction.formattedAmount(showExpenseSign: showExpenseSign)
        guard let currency,
              transaction.currency.caseInsensitiveCompare(currency) != .orderedSame,
              let amount = Decimal(string: transaction.amount, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN,
              let converted = rates?.convert(abs(amount), from: transaction.currency, to: currency) else {
            primary = saved
            original = nil
            return
        }
        primary = "≈" + MoneyFormatter.format(
            transaction.kind != .income && showExpenseSign ? -converted : converted,
            currency: currency,
            showPositiveSign: transaction.kind == .income
        )
        original = saved
    }
}
