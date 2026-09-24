import SwiftUI

struct AccountIconBadge: View {
    let iconName: String
    let color: Color
    var iconSize: CGFloat = 24

    @ScaledMetric(relativeTo: .body) private var size = 36

    var body: some View {
        AppIcon(iconName, size: iconSize)
            .foregroundStyle(AppColor.iconForeground(for: color))
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}
