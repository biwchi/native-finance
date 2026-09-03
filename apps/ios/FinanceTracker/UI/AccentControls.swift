import SwiftUI

// Keep the pair private so screens select a control, not its foreground/fill colors.
private enum AccentPalette {
    static let fill = Color("AccentColor")
    static let foreground = Color("OnAccentColor")
    static let disabledForeground = Color.primary
}

struct AccentSelectionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(isSelected && isEnabled ? AccentPalette.foreground : Color.primary)
                .background(
                    isSelected ? AccentPalette.fill : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PrimaryActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    enum Appearance: CaseIterable {
        case capsule
        case prominent
        case glass
    }

    let title: String
    let isLoading: Bool
    let appearance: Appearance
    let action: () -> Void

    init(
        _ title: String,
        isLoading: Bool = false,
        appearance: Appearance = .capsule,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.appearance = appearance
        self.action = action
    }

    var body: some View {
        Group {
            switch appearance {
            case .capsule:
                button.buttonStyle(CapsulePrimaryButtonStyle(isLoading: isLoading))
            case .prominent:
                button.buttonStyle(.borderedProminent)
            case .glass:
                if #available(iOS 26.0, *) {
                    button.buttonStyle(.glassProminent)
                } else {
                    button.buttonStyle(.borderedProminent)
                }
            }
        }
        .tint(AccentPalette.fill)
        .disabled(isLoading)
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(foreground)
                }
                Text(title)
            }
            .font(appearance == .capsule ? .headline : nil)
            .foregroundStyle(foreground)
            .frame(
                maxWidth: appearance == .prominent ? nil : .infinity,
                minHeight: appearance == .capsule ? 52 : nil
            )
        }
    }

    private var foreground: Color {
        // Native prominent/glass styles replace the accent fill when disabled.
        // Loading capsules retain their fill so their progress stays readable.
        if isLoading && appearance == .capsule { return AccentPalette.foreground }
        if !isEnabled || (isLoading && appearance != .capsule) {
            return AccentPalette.disabledForeground
        }
        return AccentPalette.foreground
    }
}

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
                .foregroundStyle(isEnabled ? AccentPalette.foreground : AccentPalette.disabledForeground)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(AccentPalette.fill)
        .accessibilityLabel(title)
    }
}

private struct CapsulePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isLoading: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(AccentPalette.fill, in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled || isLoading ? (configuration.isPressed ? 0.9 : 1) : 0.45)
    }
}

private struct AccentControlsPreview: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                AccentSelectionButton("Unselected", isSelected: false) {}
                AccentSelectionButton("Selected", isSelected: true) {}
            }
            PrimaryActionButton("Save changes") {}
            PrimaryActionButton("Saving…", isLoading: true) {}
            HStack {
                PrimaryIconButton("Review transaction", iconName: "arrow-up") {}
                PrimaryActionButton("Try Again", appearance: .prominent) {}
            }
            PrimaryActionButton("Add account", appearance: .glass) {}
                .controlSize(.large)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
    }
}

#Preview("Controls — Light") {
    AccentControlsPreview()
        .preferredColorScheme(.light)
}

#Preview("Controls — Dark") {
    AccentControlsPreview()
        .preferredColorScheme(.dark)
}
