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
    let diameter: CGFloat
    let action: () -> Void

    init(
        _ title: String,
        iconName: String,
        iconSize: CGFloat = AppControlSize.floatingButtonGlyph,
        appearance: Appearance = .filled,
        diameter: CGFloat = AppControlSize.floatingButtonDiameter,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.iconName = iconName
        self.iconSize = iconSize
        self.appearance = appearance
        self.diameter = max(AppControlSize.minimumTapTarget, diameter)
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
            button.buttonStyle(LegacyGlassStyle(diameter: diameter))
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private struct LegacyGlassStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        let diameter: CGFloat

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .frame(width: diameter, height: diameter)
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
                .frame(width: labelSize, height: labelSize)
        }
    }

    private var labelSize: CGFloat {
        appearance == .glass ? diameter - 18 : AppControlSize.minimumTapTarget
    }

    private var foreground: Color {
        if appearance == .glass {
            return isEnabled ? .primary : .secondary
        }
        return isEnabled ? AppColor.onAccent : .primary
    }
}
