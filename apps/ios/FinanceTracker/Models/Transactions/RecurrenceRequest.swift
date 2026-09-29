import Foundation

struct RecurrenceRequest: Encodable, Equatable {
    let frequency: RecurrenceFrequency
    let endAt: Date?
    var timeZone: String? = nil
}
