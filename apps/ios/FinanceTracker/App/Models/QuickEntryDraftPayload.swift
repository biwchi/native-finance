import Foundation

struct QuickEntryDraftPayload: Decodable {
    let id: UUID
    let kind: QuickEntryKind
    let accountId: UUID
    let destinationAccountId: UUID?
    let amount: String
    let currency: String
    let categoryId: UUID?
    let note: String?
    let occurredAt: Date
    let recurrence: QuickEntryRecurrence?
    let conversion: QuickEntryConversion?
    var counterparty: String? = nil
}
