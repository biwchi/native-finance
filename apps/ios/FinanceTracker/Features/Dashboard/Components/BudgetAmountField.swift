import SwiftUI

struct BudgetAmountField: View {
    let title: String
    @Binding var text: String
    let currency: String
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 0) {
                if !currency.isEmpty {
                    Text(MoneyFormatter.symbol(for: currency))
                        .foregroundStyle(.secondary)
                }

                TextField(MoneyFormatter.number(.zero), text: displayedText)
                    .fixedSize()
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .focused($isFocused)
            }
        }
    }

    private var displayedText: Binding<String> {
        Binding(
            get: {
                if isFocused { return text }
                return MoneyFormatter.parseInput(text).map(MoneyFormatter.number) ?? text
            },
            set: { text = $0.replacingOccurrences(of: ".", with: MoneyFormatter.decimalSeparator) }
        )
    }
}
