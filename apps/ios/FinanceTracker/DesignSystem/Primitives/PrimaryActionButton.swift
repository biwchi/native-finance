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
            if !isEnabled || isLoading {
                button.buttonStyle(OpaqueDisabledStyle(isLoading: isLoading, appearance: appearance))
            } else {
                switch appearance {
                case .capsule:
                    button.buttonStyle(CapsuleStyle())
                case .prominent:
                    button.buttonStyle(.borderedProminent)
                case .glass:
                    if #available(iOS 26.0, *) {
                        button.buttonStyle(.glassProminent)
                    } else {
                        button.buttonStyle(LegacyGlassStyle())
                    }
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
        if !isEnabled && !isLoading { return AppColor.disabledControlForeground }
        return AppColor.onAccent
    }

    private struct OpaqueDisabledStyle: ButtonStyle {
        @Environment(\.controlSize) private var controlSize
        let isLoading: Bool
        let appearance: Appearance

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, appearance == .capsule ? 0 : AppSpacing.large)
                .padding(.vertical, appearance == .capsule ? 0 : AppSpacing.compact)
                .frame(minHeight: minimumHeight)
                .background(isLoading ? AppColor.accent : AppColor.disabledControlFill, in: Capsule())
                .contentShape(Capsule())
        }

        private var minimumHeight: CGFloat? {
            if appearance == .capsule { return AppControlSize.primaryButtonHeight }
            if controlSize == .large || controlSize == .extraLarge { return AppControlSize.primaryButtonHeight }
            if #unavailable(iOS 26.0), appearance == .glass { return AppControlSize.minimumTapTarget }
            return nil
        }
    }

    private struct LegacyGlassStyle: ButtonStyle {
        @Environment(\.controlSize) private var controlSize

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.small)
                .frame(minHeight: controlSize == .large || controlSize == .extraLarge
                       ? AppControlSize.primaryButtonHeight : AppControlSize.minimumTapTarget)
                .background(AppColor.accent, in: Capsule())
                .contentShape(Capsule())
                .compositingGroup()
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }

    private struct CapsuleStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(AppColor.accent, in: Capsule())
                .contentShape(Capsule())
                .compositingGroup()
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}
