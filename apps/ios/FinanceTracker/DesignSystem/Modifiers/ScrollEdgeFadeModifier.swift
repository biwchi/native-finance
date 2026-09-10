import SwiftUI

/// Shared page edges, including cards drawn outside a scroll container.
struct ScrollEdgeFadeModifier<Background: View>: ViewModifier {
    let background: Background
    var bottomBackground: Color = AppColor.groupedBackground
    var usesNativeTopEdge = true

    private let fadeBelowToolbar: CGFloat = 40
    private let blurBelowToolbar: CGFloat = 12
    private let maximumToolbarOverlap: CGFloat = 44

    private var hasNativeTopEdge: Bool {
        if #available(iOS 26.0, *) { usesNativeTopEdge } else { false }
    }

    func body(content: Content) -> some View {
        content
            .modifier(NativeScrollEdges(usesNativeTopEdge: usesNativeTopEdge))
            .overlay(alignment: .top) {
                if !hasNativeTopEdge {
                    GeometryReader { proxy in
                        ZStack(alignment: .top) {
                            ScrollEdgeBlurView(
                                transitionHeight: min(proxy.safeAreaInsets.top, maximumToolbarOverlap)
                                    + blurBelowToolbar
                            )
                            .frame(height: proxy.safeAreaInsets.top + blurBelowToolbar)
                            .offset(y: -proxy.safeAreaInsets.top)

                            // Retain a translucent wash of the moving page background.
                            // The material must remain visible through it so content
                            // becomes blurred behind the toolbar instead of disappearing.
                            background
                                .ignoresSafeArea()
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
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    ScrollEdgeBlurView(transitionHeight: 64, edge: .bottom)
                        .overlay {
                            bottomBackground.mask {
                                LinearGradient(stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black.opacity(0.03), location: 0.15),
                                    .init(color: .black.opacity(0.12), location: 0.3),
                                    .init(color: .black.opacity(0.38), location: 0.5),
                                    .init(color: .black.opacity(0.85), location: 1)
                                ], startPoint: .top, endPoint: .bottom)
                            }
                        }
                        // Include floating bottom controls, but do not scale the fade to keyboard height.
                        .frame(height: (min(proxy.safeAreaInsets.bottom, 160) + 40) * 2 / 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    private struct NativeScrollEdges: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme
        let usesNativeTopEdge: Bool

        @ViewBuilder
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                // Large titles live in the scroll content on iOS 26. The native
                // soft edge keeps them above its effect, including while collapsing.
                content
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .scrollEdgeEffectHidden(!usesNativeTopEdge, for: .top)
                    .scrollEdgeEffectHidden(true, for: .bottom)
                    // Keep inline title contrast consistent with the page when
                    // a moving gradient sits behind the transparent navigation bar.
                    .toolbarColorScheme(usesNativeTopEdge ? colorScheme : nil, for: .navigationBar)
            } else {
                content
            }
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

extension View {
    @ViewBuilder
    func scrollEdgeFades(enabled: Bool = true, background: Color = AppColor.groupedBackground) -> some View {
        if enabled {
            modifier(ScrollEdgeFadeModifier(background: background, bottomBackground: background))
        } else {
            self
        }
    }
}
