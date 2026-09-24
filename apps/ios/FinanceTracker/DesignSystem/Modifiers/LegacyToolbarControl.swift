import SwiftUI

struct LegacyToolbarControl: ViewModifier {
    var isIcon = false
    var horizontalPadding: CGFloat = AppSpacing.medium

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else if isIcon {
            content
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                .modifier(LegacyGlassSurface(shape: Circle()))
                .contentShape(Circle())
        } else {
            content
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: AppControlSize.minimumTapTarget,
                       minHeight: AppControlSize.minimumTapTarget)
                .modifier(LegacyGlassSurface(shape: Capsule()))
                .contentShape(Capsule())
        }
    }
}

extension View {
    func legacyToolbarIcon() -> some View {
        modifier(LegacyToolbarControl(isIcon: true))
    }

    func legacyToolbarControl(horizontalPadding: CGFloat = AppSpacing.medium) -> some View {
        modifier(LegacyToolbarControl(horizontalPadding: horizontalPadding))
    }
}
