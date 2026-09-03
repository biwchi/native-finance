import SwiftUI

extension View {
    @ViewBuilder
    func accountSelectorGlass() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(.thinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
        }
    }
}
