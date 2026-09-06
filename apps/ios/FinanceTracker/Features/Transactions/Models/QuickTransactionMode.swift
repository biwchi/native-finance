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

    var iconName: String {
        switch self {
        case .expense: "arrow-up-right-circle"
        case .income: "arrow-down-left-circle"
        case .transfer: "coins-swap"
        case .debt: "user"
        }
    }

    var color: Color {
        switch self {
        case .expense: AppColor.warning
        case .income: AppColor.positive
        case .transfer: AppColor.informative
        case .debt: AppColor.informative
        }
    }
}
