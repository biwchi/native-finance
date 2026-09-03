import Foundation

struct RecurrenceRequest: Encodable, Equatable {
    let frequency: RecurrenceFrequency
    let endAt: Date?
}
