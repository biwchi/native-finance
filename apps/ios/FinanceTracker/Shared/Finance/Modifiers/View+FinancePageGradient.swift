import SwiftUI

private struct FinancePageGradientModifier: ViewModifier {
    let tint: Color
    let opacity: Double
    let height: CGFloat
    let backgroundColor: Color
    @State private var scrollOffset: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            page(
                content: content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newOffset in
                    scrollOffset = newOffset
                }
            )
        } else {
            page(content: content)
        }
    }

    private func page<PageContent: View>(content: PageContent) -> some View {
        ZStack(alignment: .top) {
            pageBackground

            if #available(iOS 26.0, *) {
                content
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .modifier(FinanceToolbarScrollEdgeModifier(background: pageBackground))
            } else {
                content
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        }
    }

    private var pageBackground: some View {
        let pullDownDistance = max(0, -scrollOffset)

        return ZStack(alignment: .top) {
            backgroundColor
                .ignoresSafeArea()

            LinearGradient(
                colors: [tint.opacity(opacity), backgroundColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: .top) {
                // Extend the top color without stretching the gradient's existing stops.
                tint.opacity(opacity)
                    .frame(height: pullDownDistance)
                    .offset(y: -pullDownDistance)
            }
            .offset(y: -scrollOffset)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}

extension View {
    @ViewBuilder
    func financePage(
        enabled: Bool = true,
        tint: Color = AppColor.accent,
        opacity: Double = 0.5,
        gradientHeight: CGFloat = 420,
        backgroundColor: Color = AppColor.groupedBackground
    ) -> some View {
        if enabled {
            modifier(
                FinancePageGradientModifier(
                    tint: tint,
                    opacity: opacity,
                    height: gradientHeight,
                    backgroundColor: backgroundColor
                )
            )
        } else {
            self
        }
    }

    @ViewBuilder
    func financePage<Key: PreferenceKey, DetachedContent: View>(
        enabled: Bool = true,
        detachedPreference key: Key.Type,
        tint: Color = AppColor.accent,
        opacity: Double = 0.5,
        gradientHeight: CGFloat = 420,
        backgroundColor: Color = AppColor.groupedBackground,
        @ViewBuilder detachedContent: @escaping (Key.Value, GeometryProxy) -> DetachedContent
    ) -> some View {
        if enabled {
            overlayPreferenceValue(key) { value in
                GeometryReader { proxy in
                    detachedContent(value, proxy)
                }
            }
            .modifier(
                FinancePageGradientModifier(
                    tint: tint,
                    opacity: opacity,
                    height: gradientHeight,
                    backgroundColor: backgroundColor
                )
            )
        } else {
            self
        }
    }
}
