import SwiftUI

struct CapsuleControlBackground: ViewModifier {
    enum Appearance {
        case filled
        case glass
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var appearance: Appearance = .filled

    @ViewBuilder
    func body(content: Content) -> some View {
        if appearance == .glass, !reduceTransparency {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(isEnabled), in: Capsule())
            } else {
                content.modifier(LegacyGlassSurface(shape: Capsule()))
            }
        } else {
            content.background(AppColor.controlFill, in: Capsule())
        }
    }
}
