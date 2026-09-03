import Foundation

enum DraftFieldSource: Equatable {
    case defaultValue
    case inferred
    case manual

    var isSuggested: Bool { self == .inferred }
}
