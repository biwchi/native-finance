import SwiftUI

struct TransactionAmountPanel: View {
    let expression: AmountExpression
    let formattedAmount: String

    var body: some View {
        VStack(spacing: 5) {
            if expression.rawValue.contains(where: { "+-*/".contains($0) }) {
                Text(expression.displayValue)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("Amount")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(formattedAmount)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText(value: animationValue))
                .animation(.snappy(duration: 0.24), value: animationValue)
        }
        .frame(maxWidth: .infinity, minHeight: 98, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Amount, \(formattedAmount)")
    }

    private var animationValue: Double {
        guard let result = expression.result else { return 0 }
        return NSDecimalNumber(decimal: result).doubleValue
    }
}
