import SwiftUI

/// A soft scroll edge that also covers glass cards drawn outside the list.
@available(iOS 26.0, *)
struct FinanceToolbarScrollEdgeModifier<Background: View>: ViewModifier {
    let background: Background

    private let fadeBelowToolbar: CGFloat = 40
    private let blurBelowToolbar: CGFloat = 12
    private let maximumToolbarOverlap: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectHidden(true, for: .top)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    ZStack(alignment: .top) {
                        FinanceToolbarBlurView(
                            transitionHeight: min(proxy.safeAreaInsets.top, maximumToolbarOverlap)
                                + blurBelowToolbar
                        )
                        .frame(height: proxy.safeAreaInsets.top + blurBelowToolbar)
                        .offset(y: -proxy.safeAreaInsets.top)

                        // Retain a translucent wash of the moving page background.
                        // The material must remain visible through it so content
                        // becomes blurred behind the toolbar instead of disappearing.
                        background
                            .mask(alignment: .top) {
                                edgeMask(in: proxy, stops: [
                                    .init(color: .black.opacity(0.85), location: 0),
                                    .init(color: .black.opacity(0.38), location: 0.5),
                                    .init(color: .black.opacity(0.12), location: 0.7),
                                    .init(color: .black.opacity(0.03), location: 0.85),
                                    .init(color: .clear, location: 1)
                                ])
                            }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }

    private func edgeMask(in proxy: GeometryProxy, stops: [Gradient.Stop]) -> some View {
        let topInset = proxy.safeAreaInsets.top
        let overlap = min(topInset, maximumToolbarOverlap)

        // Keep a little content visible behind the toolbar, then ease the
        // background wash out below it. Blur has its own shorter transition.
        return VStack(spacing: 0) {
            (stops.first?.color ?? .clear)
                .frame(height: topInset - overlap)
            LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                .frame(height: overlap + fadeBelowToolbar)
        }
        .offset(y: -topInset)
    }
}
