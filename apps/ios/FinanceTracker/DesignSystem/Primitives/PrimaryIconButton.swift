import SwiftUI

struct PrimaryIconButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let iconName: String
    let action: () -> Void

    init(_ title: String, iconName: String, action: @escaping () -> Void) {
        self.title = title
        self.iconName = iconName
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            AppIcon(iconName, size: 17)
                .foregroundStyle(isEnabled ? AppColor.onAccent : Color.primary)
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(AppColor.accent)
        .accessibilityLabel(title)
    }
}
