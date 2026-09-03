import SwiftUI

enum FinanceCardSurface {
    case standard
    case glass
}

extension EnvironmentValues {
    @Entry var monthlySummaryCardBackground = AppColor.summarySurface
}

extension View {
    @ViewBuilder
    func financeCardSurface(
        _ surface: FinanceCardSurface,
        fallbackColor: Color,
        cornerRadius: CGFloat
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        switch surface {
        case .standard:
            background(fallbackColor, in: shape)
        case .glass:
            if #available(iOS 26.0, *) {
                glassEffect(.regular, in: shape)
            } else {
                background(.thinMaterial, in: shape)
                    .overlay {
                        shape.stroke(.white.opacity(0.10), lineWidth: 1)
                    }
            }
        }
    }
}
