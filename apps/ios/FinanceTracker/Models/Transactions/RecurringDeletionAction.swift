import Foundation

enum RecurringDeletionAction: String, Codable, CaseIterable {
    case occurrence
    case stopRepeating
    case occurrenceAndFuture

    var title: String {
        switch self {
        case .occurrence: "Delete only this transaction"
        case .stopRepeating: "Stop repeating"
        case .occurrenceAndFuture: "Delete this and all future"
        }
    }
}
