import SwiftUI

enum QuickTransactionMode: String, CaseIterable, Identifiable {
    case income
    case expense
    case transfer
    case debt

    var id: Self { self }

    init(_ transaction: any EditableTransaction) {
        self = transaction.kind == .debt ? .debt : transaction.kind == .income ? .income : .expense
    }

    var title: String {
        rawValue.capitalized
    }

    func selectionAfterSwipe(_ translation: CGSize, among modes: [Self]) -> Self? {
        guard modes.count > 1,
              abs(translation.width) >= 80,
              abs(translation.width) > abs(translation.height) * 2,
              let index = modes.firstIndex(of: self) else { return nil }

        let step = translation.width < 0 ? 1 : -1
        return modes[(index + step + modes.count) % modes.count]
    }

    var iconName: String {
        switch self {
        case .expense: "arrow-up-right"
        case .income: "arrow-down-left"
        case .transfer: "coins-swap"
        case .debt: "user"
        }
    }

    var color: Color {
        switch self {
        case .expense: AppColor.warningText
        case .income: AppColor.positiveText
        case .transfer: AppColor.informative
        case .debt: AppColor.informative
        }
    }
}
