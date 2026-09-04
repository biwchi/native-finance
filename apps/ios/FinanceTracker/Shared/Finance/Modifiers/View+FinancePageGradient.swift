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
            backgroundColor
                .ignoresSafeArea()

            LinearGradient(
                colors: [tint.opacity(opacity), backgroundColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .offset(y: -scrollOffset)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            content
                .scrollContentBackground(.hidden)
                .background(Color.clear)
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
