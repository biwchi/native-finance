import SwiftUI

extension View {
    @ViewBuilder
    func accountSelectorGlass(isToolbarItem: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if isToolbarItem {
                // The toolbar supplies the same glass background as its other controls.
                self
            } else {
                glassEffect(.clear.interactive(), in: Capsule())
            }
        } else {
            modifier(LegacyGlassSurface(shape: Capsule()))
        }
    }
}
