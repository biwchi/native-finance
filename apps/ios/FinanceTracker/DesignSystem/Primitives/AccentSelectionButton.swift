import SwiftUI

struct AccentSelectionButton: View {
    enum Appearance {
        case filled
        case glass
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .caption) private var iconBadgeSize = 20
    @ScaledMetric(relativeTo: .caption) private var iconSpacing = AppSpacing.compact

    let title: String
    let isSelected: Bool
    let iconName: String?
    let appearance: Appearance
    let selectionTint: Color
    let action: () -> Void

    init(
        _ title: String,
        isSelected: Bool,
        iconName: String? = nil,
        appearance: Appearance = .filled,
        selectionTint: Color = AppColor.accent,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.iconName = iconName
        self.appearance = appearance
        self.selectionTint = selectionTint
        self.action = action
    }

    var body: some View {
        Group {
            switch appearance {
            case .filled:
                filledButton
            case .glass:
                glassButton
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var filledButton: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(isSelected && isEnabled ? AppColor.onAccent : Color.primary)
                .background(
                    isSelected ? AppColor.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var glassButton: some View {
        Button(action: action) {
            HStack(spacing: iconSpacing) {
                if let iconName {
                    AppIcon(iconName, size: 16, relativeTo: .caption)
                        .frame(width: iconBadgeSize, height: iconBadgeSize)
                        .background(selectionTint.opacity(isEnabled ? (isSelected ? 0.25 : 0.10) : 0.05), in: Circle())
                }
                Text(title)
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
            }
            // Semantic color lives behind the icon; text and artwork retain native contrast.
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        }
        .buttonStyle(GlassSelectionStyle(
            tint: selectionTint,
            isSelected: isSelected,
            isEnabled: isEnabled,
            reduceTransparency: reduceTransparency
        ))
    }

    private struct GlassSelectionStyle: ButtonStyle {
        let tint: Color
        let isSelected: Bool
        let isEnabled: Bool
        let reduceTransparency: Bool

        func makeBody(configuration: Configuration) -> some View {
            surface(configuration.label
                .padding(.horizontal, AppSpacing.small)
                .padding(.vertical, AppSpacing.compact)
                .frame(minHeight: AppControlSize.minimumTapTarget)
            )
            .overlay {
                Capsule().strokeBorder(tint.opacity(isSelected ? 0.55 : 0), lineWidth: 1)
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
        }

        @ViewBuilder
        private func surface<Content: View>(_ content: Content) -> some View {
            if #available(iOS 26.0, *), !reduceTransparency {
                content.glassEffect(
                    .regular.tint(isSelected ? tint.opacity(0.22) : .clear).interactive(isEnabled),
                    in: Capsule()
                )
            } else {
                content
                    .background(tint.opacity(isSelected ? 0.16 : 0), in: Capsule())
                    .background {
                        if reduceTransparency {
                            Capsule().fill(AppColor.elevatedSurface)
                        } else {
                            Capsule().fill(.thinMaterial)
                        }
                    }
            }
        }
    }
}
