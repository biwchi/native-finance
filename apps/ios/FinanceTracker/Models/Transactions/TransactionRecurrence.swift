import Foundation

struct TransactionRecurrence: Codable, Hashable {
    let id: UUID
    let frequency: RecurrenceFrequency
    let endAt: Date?
}
