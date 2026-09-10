import SwiftUI

struct LegacyToolbarControl: ViewModifier {
    var horizontalPadding: CGFloat = AppSpacing.medium

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
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
    func legacyToolbarControl(horizontalPadding: CGFloat = AppSpacing.medium) -> some View {
        modifier(LegacyToolbarControl(horizontalPadding: horizontalPadding))
    }

    @ViewBuilder
    func legacySheetAppearance() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            presentationCornerRadius(AppRadius.composer)
        }
    }

}
