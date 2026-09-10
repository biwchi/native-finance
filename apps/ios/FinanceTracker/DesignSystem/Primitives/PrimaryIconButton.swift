import SwiftUI

struct PrimaryIconButton: View {
    enum Appearance {
        case filled
        case glass
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
        if #available(iOS 26.0, *), appearance == .glass {
            button.buttonStyle(.glass(.regular.tint(AppColor.accent.opacity(0.22))))
        } else if appearance == .glass {
            button.buttonStyle(LegacyGlassStyle())
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private struct LegacyGlassStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .frame(width: AppControlSize.floatingButtonDiameter,
                       height: AppControlSize.floatingButtonDiameter)
                .modifier(LegacyGlassSurface(shape: Circle(), tint: AppColor.accent.opacity(0.22)))
                .contentShape(Circle())
                .compositingGroup()
                .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.45)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
        }
    }

    private var button: some View {
        Button(action: action) {
            AppIcon(iconName, size: iconSize)
                .foregroundStyle(foreground)
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
        }
    }

    private var foreground: Color {
        if appearance == .glass {
            return isEnabled ? .primary : .secondary
        }
        return isEnabled ? AppColor.onAccent : .primary
    }
}
