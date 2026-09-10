import SwiftUI

/// Keeps the geometry of glass controls on systems without Liquid Glass.
struct LegacyGlassSurface<Surface: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: Surface
    var tint: Color = .clear

    func body(content: Content) -> some View {
        content
            .background(tint, in: shape)
            .background {
                if reduceTransparency {
                    shape.fill(AppColor.elevatedSurface)
                } else {
                    shape.fill(.thinMaterial)
                }
            }
            .overlay {
                shape.stroke(.primary.opacity(0.08), lineWidth: 0.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
