import Foundation

struct QuickEntryInterpretationResponse: Decodable {
    let referenceNow: Date
    let transactions: [QuickEntryDraftPayload]
}
