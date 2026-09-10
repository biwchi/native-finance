import Foundation

struct QuickEntryDraft: Codable, Equatable, Identifiable, EditableTransaction {
    let id: UUID
    var mode: QuickTransactionMode
    var accountId: UUID
    var destinationAccountId: UUID?
    var amount: String
    var currency: String
    var category: TransactionCategory?
    var merchant: String?
    var payee: String?
    var note: String?
    var occurredAt: Date
    var isRecurring: Bool
    var recurrenceFrequency: RecurrenceFrequency
    var recurrenceEndAt: Date?
    let sourceText: String
    var conversion: QuickEntryConversion?
    var warnings: [String]

    init(payload: QuickEntryDraftPayload, category: TransactionCategory?) {
        id = payload.id
        mode = switch payload.kind {
        case .expense: .expense
        case .income: .income
        case .transfer: .transfer
        }
        accountId = payload.accountId
        destinationAccountId = payload.destinationAccountId
        amount = payload.amount
        currency = payload.currency
        self.category = category
        merchant = payload.merchant
        payee = payload.payee
        note = payload.note
        occurredAt = payload.occurredAt
        isRecurring = payload.recurrence != nil
        recurrenceFrequency = payload.recurrence?.frequency ?? .monthly
        recurrenceEndAt = payload.recurrence?.endAt
        sourceText = payload.sourceText
        conversion = payload.conversion
        warnings = payload.warnings
    }

    var kind: TransactionKind {
        mode == .income ? .income : .expense
    }

    var recurrence: TransactionRecurrence? {
        guard isRecurring, mode != .transfer else { return nil }
        return TransactionRecurrence(
            id: id,
            frequency: recurrenceFrequency,
            endAt: recurrenceEndAt
        )
    }
}
