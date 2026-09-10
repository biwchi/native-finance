import SwiftUI

struct TransactionGlassSurface<Surface: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled
    let shape: Surface
    var isInteractive = false

    private var backgroundColor: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(backgroundColor, in: shape)
        } else if #available(iOS 26.0, *) {
            // A shared base keeps controls and larger containers the same shade.
            content
                .background(backgroundColor, in: shape)
                .glassEffect(.clear.interactive(isInteractive && isEnabled), in: shape)
        } else {
            content
                .background(backgroundColor, in: shape)
                .modifier(LegacyGlassSurface(shape: shape))
        }
    }
}
