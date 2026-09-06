import SwiftUI

struct TransactionAmountText: View {
    let amount: String
    var font: Font = .subheadline.weight(.semibold)
    var color: Color = .primary

    var body: some View {
        Text(styledAmount)
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
    }

    private var styledAmount: AttributedString {
        var text = AttributedString(amount)
        if let separator = text.range(of: MoneyFormatter.decimalSeparator) {
            let fraction = separator.lowerBound..<text.endIndex
            text[fraction].font = .caption
            text[fraction].foregroundColor = .secondary
        }
        return text
    }
}
