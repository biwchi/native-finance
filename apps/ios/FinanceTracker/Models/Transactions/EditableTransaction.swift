import Foundation

protocol EditableTransaction {
    var accountId: UUID { get }
    var kind: TransactionKind { get }
    var amount: String { get }
    var currency: String { get }
    var category: TransactionCategory? { get }
    var merchant: String? { get }
    var payee: String? { get }
    var note: String? { get }
    var occurredAt: Date { get }
    var recurrence: TransactionRecurrence? { get }
}

extension EditableTransaction {
    func formattedAmount(showExpenseSign: Bool = true) -> String {
        guard let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else {
            return "Unavailable"
        }
        return MoneyFormatter.format(
            kind == .expense && showExpenseSign ? -value : value,
            currency: currency,
            showPositiveSign: kind == .income
        )
    }
}
