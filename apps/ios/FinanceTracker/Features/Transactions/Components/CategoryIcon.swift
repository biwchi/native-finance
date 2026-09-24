import SwiftUI

struct CategoryIcon: View {
    let iconName: String
    let color: Color
    var size: CGFloat

    init(category: TransactionCategory, size: CGFloat = 36) {
        self.init(iconName: category.displayIcon, color: category.displayColor, size: size)
    }

    init(iconName: String, color: Color, size: CGFloat = 36) {
        self.iconName = iconName
        self.color = color
        self.size = size
    }

    var body: some View {
        AppIcon(iconName, size: size * 0.43)
            .foregroundStyle(AppColor.iconForeground(for: color))
            .frame(width: size, height: size)
            .background(
                color.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.28)
            )
            .accessibilityHidden(true)
    }
}
