import SwiftUI

extension TransactionCategory {
    var displayIcon: String {
        AppIcons.canonicalName(icon ?? legacyAppearance.symbol)
    }

    var displayColor: Color {
        displayCategoryColor.swiftUIColor
    }

    var displayCategoryColor: CategoryColor {
        color ?? legacyAppearance.color
    }

    private var legacyAppearance: (symbol: String, color: CategoryColor) {
        switch systemKey {
        case "expense.food-drink": ("cutlery", .orange)
        case "expense.groceries": ("cart", .green)
        case "expense.fuel": ("gas", .orange)
        case "expense.transport": ("car", .blue)
        case "expense.housing": ("home-simple", .indigo)
        case "expense.utilities": ("flash", .orange)
        case "expense.shopping": ("shopping-bag", .pink)
        case "expense.health": ("healthcare", .red)
        case "expense.insurance": ("shield", .teal)
        case "expense.entertainment": ("bookmark-book", .purple)
        case "expense.education": ("book", .indigo)
        case "expense.travel": ("airplane", .cyan)
        case "expense.subscriptions": ("repeat", .purple)
        case "expense.fees-charges": ("percentage", .gray)
        case "expense.gifts-donations": ("gift", .pink)
        case "income.salary": ("cash", .green)
        case "income.business-freelance": ("suitcase", .blue)
        case "income.investments": ("graph-up", .teal)
        case "income.refunds": ("undo", .orange)
        case "income.gifts-received": ("gift", .pink)
        default: ("label", kind == .income ? .green : .gray)
        }
    }
}
