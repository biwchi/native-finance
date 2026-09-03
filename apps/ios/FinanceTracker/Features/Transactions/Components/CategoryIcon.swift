import SwiftUI

struct CategoryIcon: View {
    let category: TransactionCategory
    var size: CGFloat = 36

    var body: some View {
        AppIcon(category.displayIcon, size: size * 0.43)
            .foregroundStyle(category.displayColor)
            .frame(width: size, height: size)
            .background(
                category.displayColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.28)
            )
            .accessibilityHidden(true)
    }
}
