import SwiftUI

struct TransactionGlassSurface<Surface: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: Surface

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(AppColor.elevatedSurface, in: shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.thinMaterial, in: shape)
        }
    }
}
