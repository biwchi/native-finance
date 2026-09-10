import Foundation

struct QuickEntryRequest: Encodable {
    let text: String
    let defaultAccountId: UUID
    let locale: String
    let timeZone: String
    var context: QuickEntryLocalContext? = nil
}
