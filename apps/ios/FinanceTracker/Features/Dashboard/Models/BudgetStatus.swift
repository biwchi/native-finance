import SwiftUI

enum BudgetStatus: Equatable {
    case onTrack
    case watchSpending
    case nearLimit
    case overLimit

    var displayText: String {
        switch self {
        case .onTrack: String(localized: "On track")
        case .watchSpending: String(localized: "Watch spending")
        case .nearLimit: String(localized: "Near limit")
        case .overLimit: String(localized: "Over limit")
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .watchSpending:
            String(localized: "Watch spending. Spending is ahead of this month's pace.")
        default: displayText
        }
    }
}
