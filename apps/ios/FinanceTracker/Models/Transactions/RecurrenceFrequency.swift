import Foundation

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}
