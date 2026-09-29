import Foundation

struct TransactionRecurrence: Codable, Hashable {
    let id: UUID
    let frequency: RecurrenceFrequency
    let endAt: Date?
    var timeZone: String? = nil
}
