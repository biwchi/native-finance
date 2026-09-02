import SwiftUI

// Keep the pair private so screens select a control, not its foreground/fill colors.
private enum AccentPalette {
    static let fill = Color("AccentColor")
    static let foreground = Color("OnAccentColor")
}

struct AccentSelectionButton: View {
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
                .foregroundStyle(isSelected ? AccentPalette.foreground : Color.primary)
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
                button.buttonStyle(CapsulePrimaryButtonStyle())
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
                        .tint(AccentPalette.foreground)
                }
                Text(title)
            }
            .font(appearance == .capsule ? .headline : nil)
            .foregroundStyle(AccentPalette.foreground)
            .frame(
                maxWidth: appearance == .prominent ? nil : .infinity,
                minHeight: appearance == .capsule ? 52 : nil
            )
        }
    }
}

struct PrimaryIconButton: View {
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
                .foregroundStyle(AccentPalette.foreground)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(AccentPalette.fill, in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
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
