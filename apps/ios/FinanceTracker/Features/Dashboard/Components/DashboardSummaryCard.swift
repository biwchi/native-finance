import SwiftUI

struct DashboardSummaryCard: View {
    let insights: DashboardInsights
    let currency: String
    var budgetTimeRemaining: String? = nil
    var comparisonDescription = "Compared with the previous period"

    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 34

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            if dynamicTypeSize.isAccessibilitySize {
                stackedHeader
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppSpacing.medium) {
                        headline.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        trend.fixedSize(horizontal: true, vertical: false)
                    }
                    stackedHeader
                }
            }

            if insights.hasBudget, let limit = insights.monthlyLimit {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    BudgetProgressBar(
                        budgetProgress: NSDecimalNumber(decimal: insights.budgetProgress ?? 0).doubleValue,
                        monthProgress: nil,
                        tint: AppColor.accent
                    )
                    (
                        Text(money(insights.spent)).foregroundStyle(.primary)
                        + Text(" of \(money(limit)) used")
                        + Text(budgetTimeRemaining.map { " · \($0)" } ?? "")
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(spoken(insights.spent)) of \(spoken(limit)) used. \(budgetTimeRemaining ?? "")")
                }
            }

            Divider()
            if dynamicTypeSize.isAccessibilitySize {
                stackedMetrics
            } else {
                HStack(alignment: .top, spacing: AppSpacing.small) {
                    metric("Income", amount: insights.income, compact: true)
                    Divider()
                    metric("Spent", amount: insights.spent, compact: true)
                    if insights.hasBudget {
                        Divider()
                        metric("Net", amount: insights.net, signed: true, compact: true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .financeCardSurface(.clearGlass, fallbackColor: AppColor.elevatedSurface, cornerRadius: AppRadius.extraLarge)
        .accessibilityElement(children: .contain)
    }

    private var stackedHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            headline
            trend
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
            Text(insights.hasBudget ? "Budget left" : "Net")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(money(insights.hasBudget ? (insights.remaining ?? 0) : insights.net, signed: !insights.hasBudget))
                .font(.system(size: amountSize, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(insights.hasBudget ? "Budget left" : "Net")
        .accessibilityValue(spoken(insights.hasBudget ? (insights.remaining ?? 0) : insights.net))
    }

    @ViewBuilder
    private var trend: some View {
        if let percent = insights.comparisonPercent {
            let color = percent < 0 ? AppColor.positiveText : percent > 0 ? AppColor.destructiveText : Color.secondary
            HStack(spacing: AppSpacing.extraSmall) {
                if percent != 0 {
                    AppIcon(percent < 0 ? "trade-down" : "trade-up", size: 14, relativeTo: .caption2)
                }
                Text(trendText(percent))
                    .font(.caption2.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.compact)
            .padding(.vertical, AppSpacing.extraSmall)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.small))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(trendText(percent))
            .accessibilityValue(comparisonDescription)
        }
    }

    private var stackedMetrics: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            metric("Income", amount: insights.income)
            Divider()
            metric("Spent", amount: insights.spent)
            if insights.hasBudget {
                Divider()
                metric("Net", amount: insights.net, signed: true)
            }
        }
    }

    private func metric(_ title: String, amount: Decimal, signed: Bool = false, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Group {
                if compact {
                    ViewThatFits(in: .horizontal) {
                        metricAmount(amount, signed: signed, font: .headline)
                            .fixedSize(horizontal: true, vertical: true)
                        metricAmount(amount, signed: signed, font: .caption)
                            .fixedSize(horizontal: true, vertical: true)
                        metricAmount(amount, signed: signed, font: .caption)
                    }
                } else {
                    metricAmount(amount, signed: signed, font: .headline)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken(amount))
    }

    private func metricAmount(_ amount: Decimal, signed: Bool, font: Font) -> some View {
        Text(money(amount, signed: signed))
            .font(font.weight(.medium))
            .foregroundStyle(signed && amount != 0 ? (amount > 0 ? AppColor.positiveText : AppColor.destructiveText) : .primary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .fixedSize(horizontal: false, vertical: true)
    }

    private func trendText(_ percent: Decimal) -> String {
        guard percent != 0 else { return "Same spending" }
        let percentage = abs(percent) < 1 ? "<1" : abs(percent).formatted(.number.precision(.fractionLength(0)).locale(locale))
        return "\(percentage)% \(percent < 0 ? "less" : "more") spent"
    }

    private func money(_ amount: Decimal, signed: Bool = false) -> String {
        MoneyFormatter.format(amount, currency: currency, showPositiveSign: signed, roundToWhole: roundTotals)
    }

    private func spoken(_ amount: Decimal) -> String {
        MoneyFormatter.spoken(amount, currency: currency, locale: locale, roundToWhole: roundTotals)
    }
}
