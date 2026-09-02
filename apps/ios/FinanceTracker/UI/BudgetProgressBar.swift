import SwiftUI

/// A read-only pace indicator. The tick represents elapsed time, never the spend value.
struct BudgetProgressBar: View {
    let budgetProgress: Double
    let monthProgress: Double?
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 0)
            let fillWidth = width * clamped(budgetProgress)
            let tickWidth = min(contrast == .increased ? 3.0 : 2.0, width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(contrast == .increased ? 0.24 : 0.09))
                    .frame(height: 6)

                Capsule()
                    .fill(tint)
                    .frame(width: fillWidth, height: 6)

                if let monthProgress {
                    let offset = min(max(width * clamped(monthProgress) - tickWidth / 2, 0),
                                     max(width - tickWidth, 0))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(contrast == .increased ? 1 : 0.75))
                        .frame(width: tickWidth, height: 12)
                        .offset(x: layoutDirection == .rightToLeft ? -offset : offset)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: budgetProgress)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: monthProgress)
        .accessibilityHidden(true)
    }

    private func clamped(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }
}
