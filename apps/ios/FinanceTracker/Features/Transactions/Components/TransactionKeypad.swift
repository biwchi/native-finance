import SwiftUI

struct TransactionKeypad: View {
    let onKey: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.small), count: 4)
    private let rows = [
        ["1", "2", "3", "+"],
        ["4", "5", "6", "-"],
        ["7", "8", "9", "*"],
        [MoneyFormatter.decimalSeparator, "0", "⌫", "/"],
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.small) {
            ForEach(rows.flatMap { $0 }, id: \.self) { key in
                Button {
                    onKey(key)
                } label: {
                    Group {
                        if key == "⌫" {
                            AppIcon("erase")
                        } else {
                            Text(key == "*" ? "×" : key == "/" ? "÷" : key)
                        }
                    }
                    .font(.title2.weight(isOperator(key) ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: AppControlSize.primaryButtonHeight)
                    .modifier(QuickKeyBackground(isUtility: isOperator(key) || key == "⌫"))
                }
                .buttonStyle(KeyButtonStyle())
                .accessibilityLabel(accessibilityLabel(for: key))
            }
        }
    }

    private func isOperator(_ key: String) -> Bool {
        ["+", "-", "*", "/"].contains(key)
    }

    private func accessibilityLabel(for key: String) -> String {
        switch key {
        case "+": "Plus"
        case "-": "Minus"
        case "*": "Multiply"
        case "/": "Divide"
        case ",", ".": "Decimal separator"
        case "⌫": "Delete"
        default: key
        }
    }

    private struct KeyButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
        }
    }
}
