import SwiftUI

extension BudgetStatus {
    var tint: Color {
        switch self {
        case .onTrack: AppColor.accent
        case .watchSpending, .nearLimit: AppColor.warning
        case .overLimit: AppColor.destructive
        }
    }
}
