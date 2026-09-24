import Foundation

struct QuickEntryDraft: Codable, Equatable, Identifiable, EditableTransaction {
    let id: UUID
    var mode: QuickTransactionMode
    var accountId: UUID
    var destinationAccountId: UUID?
    var amount: String
    var currency: String
    var category: TransactionCategory?
    var note: String?
    var occurredAt: Date
    var isRecurring: Bool
    var recurrenceFrequency: RecurrenceFrequency
    var recurrenceEndAt: Date?
    var conversion: QuickEntryConversion?
    var debt: Debt? = nil
    var counterparty: String? = nil

    /// CSV rows represent recorded transactions and never recreate recurring schedules.
    init(record: TransactionRequest, category: TransactionCategory?, debt: Debt?) {
        id = UUID()
        mode = record.kind == .debt ? .debt : record.kind == .income ? .income : .expense
        accountId = record.accountId
        amount = record.amount.hasPrefix("-") ? String(record.amount.dropFirst()) : record.amount
        currency = record.currency ?? ""
        self.category = category
        self.debt = debt
        counterparty = record.counterparty
        note = record.note
        occurredAt = record.occurredAt
        isRecurring = false
        recurrenceFrequency = .monthly
    }

    init(payload: QuickEntryDraftPayload, category: TransactionCategory?) {
        id = payload.id
        mode = switch payload.kind {
        case .expense: .expense
        case .income: .income
        case .transfer: .transfer
        }
        accountId = payload.accountId
        destinationAccountId = payload.destinationAccountId
        amount = payload.amount.hasPrefix("-") ? String(payload.amount.dropFirst()) : payload.amount
        currency = payload.currency
        self.category = category
        counterparty = payload.counterparty
        note = payload.note
        occurredAt = payload.occurredAt
        isRecurring = payload.recurrence != nil
        recurrenceFrequency = payload.recurrence?.frequency ?? .monthly
        recurrenceEndAt = payload.recurrence?.endAt
        conversion = payload.conversion
    }

    var kind: TransactionKind {
        mode == .debt ? .debt : mode == .income ? .income : .expense
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
