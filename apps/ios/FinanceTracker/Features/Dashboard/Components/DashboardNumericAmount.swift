import SwiftUI

/// Keep decimal money values intact; Double is only used to direct the digit transition.
struct DashboardNumericAmount: ViewModifier {
    let amount: Decimal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText(value: NSDecimalNumber(decimal: amount).doubleValue))
            .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3), value: amount)
    }
}
