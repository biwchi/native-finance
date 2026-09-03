import SwiftUI

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
