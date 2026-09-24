import SwiftUI

struct DebtIcon: View {
    let iconName: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    init(debt: Debt, size: CGFloat = 36) {
        self.init(iconName: debt.icon ?? "user", color: (debt.color ?? .blue).swiftUIColor, size: size)
    }

    init(iconName: String, color: Color, size: CGFloat = 36) {
        self.iconName = iconName
        self.color = color
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        AppIcon(iconName, size: 24)
            .foregroundStyle(AppColor.iconForeground(for: color))
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}
