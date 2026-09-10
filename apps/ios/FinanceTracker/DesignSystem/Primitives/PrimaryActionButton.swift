import SwiftUI

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
                button.buttonStyle(CapsuleStyle(isLoading: isLoading))
            case .prominent:
                button.buttonStyle(.borderedProminent)
            case .glass:
                if #available(iOS 26.0, *) {
                    button.buttonStyle(.glassProminent)
                } else {
                    button.buttonStyle(LegacyGlassStyle(isLoading: isLoading))
                }
            }
        }
        .buttonBorderShape(.capsule)
        .tint(AppColor.accent)
        .disabled(isLoading)
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.small) {
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
                minHeight: appearance == .capsule ? AppControlSize.primaryButtonHeight : nil
            )
        }
    }

    private var foreground: Color {
        // The custom capsule retains its accent fill when disabled or loading.
        if appearance == .capsule { return AppColor.onAccent }
        if #unavailable(iOS 26.0), appearance == .glass { return AppColor.onAccent }
        if !isEnabled || (isLoading && appearance != .capsule) { return .primary }
        return AppColor.onAccent
    }

    private struct LegacyGlassStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize
        let isLoading: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.small)
                .frame(minHeight: controlSize == .large || controlSize == .extraLarge
                       ? AppControlSize.primaryButtonHeight : AppControlSize.minimumTapTarget)
                .background(AppColor.accent, in: Capsule())
                .contentShape(Capsule())
                .compositingGroup()
                .opacity(isEnabled || isLoading ? (configuration.isPressed ? 0.9 : 1) : 0.45)
        }
    }

    private struct CapsuleStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        let isLoading: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(AppColor.accent, in: Capsule())
                .contentShape(Capsule())
                .compositingGroup()
                .opacity(isEnabled || isLoading ? (configuration.isPressed ? 0.9 : 1) : 0.45)
        }
    }
}
