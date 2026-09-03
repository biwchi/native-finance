import SwiftUI

struct FinanceMetricCards: View {
    struct Metric {
        let title: String
        let amount: Decimal
        var signed = false
        var amountColor: Color = .primary
    }
    let first: Metric
    let second: Metric
    let currency: String
    var surface: FinanceCardSurface = .standard
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedCards
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppSpacing.medium) {
                        card(first, wrapsAmount: false)
                        card(second, wrapsAmount: false)
                    }
                    stackedCards
                }
            }
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var stackedCards: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            card(first, wrapsAmount: true)
            card(second, wrapsAmount: true)
        }
    }

    private func card(_ metric: Metric, wrapsAmount: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(metric.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(MoneyFormatter.format(metric.amount, currency: currency, showPositiveSign: metric.signed))
                .font(.headline)
                .foregroundStyle(metric.amountColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .fixedSize(horizontal: !wrapsAmount, vertical: true)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .financeCardSurface(
            surface,
            fallbackColor: AppColor.elevatedSurface,
            cornerRadius: AppRadius.large
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(MoneyFormatter.spoken(metric.amount, currency: currency, locale: locale))
    }
}
