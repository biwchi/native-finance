import Foundation

struct AddTransactionPresentation: Identifiable {
    let id = UUID()
    let command: String?
    let accountID: UUID?
}

struct QuickEntryRequest: Encodable {
    let text: String
    let defaultAccountId: UUID
    let locale: String
    let timeZone: String
}

struct QuickEntryInterpretationResponse: Decodable {
    let referenceNow: Date
    let transactions: [QuickEntryDraftPayload]
    let unparsedText: [String]
}

struct QuickEntryDraftPayload: Decodable {
    let id: UUID
    let kind: QuickEntryKind
    let accountId: UUID
    let destinationAccountId: UUID?
    let amount: String
    let currency: String
    let categoryId: UUID?
    let merchant: String?
    let payee: String?
    let note: String?
    let occurredAt: Date
    let recurrence: QuickEntryRecurrence?
    let sourceText: String
    let conversion: QuickEntryConversion?
    let warnings: [String]
}

enum QuickEntryKind: String, Decodable {
    case expense
    case income
    case transfer
}

struct QuickEntryRecurrence: Codable, Equatable {
    let frequency: RecurrenceFrequency
    let endAt: Date?
}

struct QuickEntryConversion: Decodable, Equatable {
    let originalAmount: String
    let originalCurrency: String
    let convertedAmount: String
    let convertedCurrency: String
    let rate: String
    let effectiveDate: String
    let stale: Bool
}

struct QuickEntryReviewPresentation: Identifiable {
    let id = UUID()
    let prompt: String
    var drafts: [QuickEntryDraft]
    let unparsedText: [String]
}

struct QuickEntryDraft: Identifiable, EditableTransaction {
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

struct TransactionBatchRequest: Encodable {
    let transactions: [TransactionBatchItem]
}

enum TransactionBatchItem: Encodable {
    case transaction(TransactionRequest)
    case transfer(TransferRequest)

    private enum CodingKeys: String, CodingKey {
        case type
        case transaction
        case transfer
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .transaction(transaction):
            try container.encode("transaction", forKey: .type)
            try container.encode(transaction, forKey: .transaction)
        case let .transfer(transfer):
            try container.encode("transfer", forKey: .type)
            try container.encode(transfer, forKey: .transfer)
        }
    }
}

struct TransactionBatchResponse: Decodable {
    let created: Int
}
