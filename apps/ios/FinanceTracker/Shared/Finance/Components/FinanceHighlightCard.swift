import SwiftUI

struct FinanceHighlightCard<Content: View>: View {
    let title: String
    let amount: Decimal
    let currency: String
    var detail: String? = nil
    var amountColor: Color = .primary
    @ViewBuilder let content: Content

    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 34

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(MoneyFormatter.format(amount, currency: currency, roundToWhole: roundTotals))
                    .font(.system(size: amountSize, weight: .semibold))
                    .foregroundStyle(amountColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(MoneyFormatter.spoken(
                        amount, currency: currency, locale: locale, roundToWhole: roundTotals
                    ))
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .financeCardSurface(.standard, fallbackColor: AppColor.elevatedSurface, cornerRadius: AppRadius.extraLarge)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .contain)
    }
}
