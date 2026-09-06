import SwiftUI

struct DebtIcon: View {
    let debt: Debt
    var size: CGFloat = 36

    var body: some View {
        AppIcon(debt.icon ?? "user", size: size * 0.43)
            .foregroundStyle((debt.color ?? .blue).swiftUIColor)
            .frame(width: size, height: size)
            .background((debt.color ?? .blue).swiftUIColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}
