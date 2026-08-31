import SwiftUI

struct CategoryIcon: View {
    let category: TransactionCategory
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: category.appearance.symbol)
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(category.appearance.color)
            .frame(width: size, height: size)
            .background(
                category.appearance.color.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.28)
            )
            .accessibilityHidden(true)
    }
}

private extension TransactionCategory {
    var appearance: (symbol: String, color: Color) {
        switch systemKey {
        case "expense.food-drink": ("fork.knife", .orange)
        case "expense.groceries": ("basket.fill", .green)
        case "expense.fuel": ("fuelpump.fill", .orange)
        case "expense.transport": ("car.fill", .blue)
        case "expense.housing": ("house.fill", .indigo)
        case "expense.utilities": ("bolt.fill", .orange)
        case "expense.shopping": ("bag.fill", .pink)
        case "expense.health": ("cross.case.fill", .red)
        case "expense.insurance": ("shield.fill", .teal)
        case "expense.entertainment": ("ticket.fill", .purple)
        case "expense.education": ("book.fill", .indigo)
        case "expense.travel": ("airplane", .cyan)
        case "expense.subscriptions": ("repeat", .purple)
        case "expense.fees-charges": ("percent", .gray)
        case "expense.gifts-donations": ("gift.fill", .pink)
        case "income.salary": ("banknote.fill", .green)
        case "income.business-freelance": ("briefcase.fill", .blue)
        case "income.investments": ("chart.line.uptrend.xyaxis", .teal)
        case "income.refunds": ("arrow.uturn.backward", .orange)
        case "income.gifts-received": ("gift.fill", .pink)
        default: ("tag.fill", kind == .income ? .green : .gray)
        }
    }
}
