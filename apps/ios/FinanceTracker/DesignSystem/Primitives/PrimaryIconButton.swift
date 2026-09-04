import SwiftUI

struct PrimaryIconButton: View {
    enum Appearance {
        case filled
        case glassProminent
    }

    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let iconName: String
    let iconSize: CGFloat
    let appearance: Appearance
    let action: () -> Void

    init(
        _ title: String,
        iconName: String,
        iconSize: CGFloat = 26,
        appearance: Appearance = .filled,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.iconName = iconName
        self.iconSize = iconSize
        self.appearance = appearance
        self.action = action
    }

    var body: some View {
        styledButton
            .buttonBorderShape(.circle)
            .tint(AppColor.accent)
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private var styledButton: some View {
        if #available(iOS 26.0, *), appearance == .glassProminent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private var button: some View {
        Button(action: action) {
            AppIcon(iconName, size: iconSize)
                .foregroundStyle(isEnabled ? AppColor.onAccent : Color.primary)
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
        }
    }
}
