import SwiftUI

struct MonthlySummaryAmount: View {
    let amount: String
    var suffix: String = ""

    @ScaledMetric(relativeTo: .title) private var amountSize = 32

    var body: some View {
        (
            Text(amount)
                .font(.system(size: amountSize, weight: .semibold))
            + Text(suffix.isEmpty ? "" : " " + suffix)
                .font(.title3.weight(.regular))
        )
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .contentTransition(.numericText())
    }
}
