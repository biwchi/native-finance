import Foundation

struct QuickEntryRecurrence: Codable, Equatable {
    let frequency: RecurrenceFrequency
    let endAt: Date?
    var timeZone: String? = nil
}
