import SwiftUI

struct DashboardSummaryCard: View {
    let insights: DashboardInsights
    let currency: String
    var budgetTimeRemaining: String? = nil
    var comparisonDescription = "Compared with the previous period"
    var onViewBudget: (() -> Void)? = nil
    var onViewMetric: ((DashboardSummaryMetrics.Metric) -> Void)? = nil
    var presentationHeight: CGFloat? = nil
    var showsMetrics = true
    var spendingTitle = "Spent this month"

    private struct Presentation: Hashable {
        let hasBudget: Bool
        let currency: String
    }

    private var presentation: Presentation {
        Presentation(hasBudget: insights.hasBudget, currency: currency)
    }

    private struct BudgetNavigationBoundsKey: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil

        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = nextValue() ?? value
        }
    }

    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var amountSize = 19

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardContent
                .fixedSize(horizontal: false, vertical: true)
                .transaction { $0.animation = nil }
                .id(presentation)
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeIn(duration: 0.18).delay(reduceMotion ? 0 : 0.12)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: presentationHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous))
        .animation(.linear(duration: 0.3), value: presentation)
        // The glass has its own stable identity and always fills the displayed height.
        // Only the content above is replaced and faded when the metric changes.
        .background {
            Color.clear
                .financeCardSurface(.clearGlass, fallbackColor: AppColor.elevatedSurface, cornerRadius: AppRadius.extraLarge)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                summaryHeader

                if insights.hasBudget, let limit = insights.monthlyLimit {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        BudgetProgressBar(
                            budgetProgress: NSDecimalNumber(decimal: insights.budgetProgress ?? 0).doubleValue,
                            monthProgress: nil,
                            tint: !showsMetrics && (insights.remaining ?? 0) < 0 ? BudgetStatus.overLimit.tint : AppColor.accent
                        )
                        budgetUsage(limit)
                            .modifier(DashboardNumericAmount(amount: insights.spent))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: limit)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("\(spoken(insights.spent)) of \(spoken(limit)) used")
                        trend
                    }
                }
                if !showsMetrics, !insights.hasBudget {
                    Text("No overall monthly limit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if showsMetrics {
                Divider()
                    .padding(.top, AppSpacing.extraLarge)
                    .padding(.bottom, AppSpacing.large)
                DashboardSummaryMetrics(insights: insights, currency: currency, isInteractive: onViewMetric != nil)
            }
        }
        .padding(AppSpacing.extraLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .allowsHitTesting(false)
        .overlayPreferenceValue(BudgetNavigationBoundsKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, let onViewBudget {
                    let bounds = proxy[anchor]
                    Button(action: onViewBudget) {
                        budgetNavigationContent
                            // Expand the touch target without changing the header layout.
                            .frame(
                                width: bounds.width + AppSpacing.compact * 2,
                                height: max(44, bounds.height)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small))
                    }
                    .buttonStyle(BudgetLinkButtonStyle())
                    .accessibilityLabel("View budget")
                    .accessibilityHint("Opens the budget for the selected month and account")
                    .accessibilityIdentifier("budgetSummaryNavigation")
                    .position(x: bounds.midX, y: bounds.midY)
                }
            }
        }
        .overlayPreferenceValue(DashboardSummaryMetrics.BoundsKey.self) { anchors in
            GeometryReader { proxy in
                if let onViewMetric {
                    ForEach(DashboardSummaryMetrics.Metric.allCases) { metric in
                        if let metricAnchors = anchors[metric], !metricAnchors.isEmpty {
                            let bounds = metricAnchors.reduce(CGRect.null) { $0.union(proxy[$1]) }
                            Button { onViewMetric(metric) } label: {
                                Color.clear
                                    .frame(width: max(44, bounds.width), height: max(44, bounds.height))
                                    .contentShape(RoundedRectangle(cornerRadius: AppRadius.small))
                            }
                            .buttonStyle(MetricButtonStyle(
                                highlightPadding: AppSpacing.compact,
                                highlightCornerRadius: AppRadius.small
                            ))
                            .accessibilityLabel(metric.title)
                            .accessibilityValue(MoneyFormatter.spoken(metric.amount(in: insights), currency: currency, locale: locale))
                            .accessibilityHint("Show exact amount")
                            .accessibilityIdentifier("summaryMetric-\(metric.rawValue)")
                            .position(x: bounds.midX, y: bounds.midY)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var summaryHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedHeader
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    headline.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    headerAccessory
                }
                stackedHeader
            }
        }
    }

    @ViewBuilder
    private var headerAccessory: some View {
        if insights.hasBudget {
            if showsMetrics {
                budgetNavigationLabel
            }
        } else {
            trend
        }
    }

    private func budgetUsage(_ limit: Decimal) -> Text {
        Text(money(insights.spent).replacingOccurrences(of: " ", with: "\u{00A0}"))
            .foregroundStyle(.primary)
        + Text(" of \(money(limit).replacingOccurrences(of: " ", with: "\u{00A0}")) used")
    }

    private var budgetNavigationLabel: some View {
        budgetNavigationContent
            // Reserve layout space while the overlay renders the interactive label.
            .opacity(onViewBudget == nil ? 1 : 0)
            .anchorPreference(key: BudgetNavigationBoundsKey.self, value: .bounds) { $0 }
            .accessibilityHidden(onViewBudget != nil)
    }

    private var budgetNavigationContent: some View {
        HStack(spacing: AppSpacing.extraSmall) {
            Text("View budget")
                .font(.subheadline.weight(.medium))
            AppIcon("nav-arrow-right", size: 14, relativeTo: .subheadline)
        }
        .foregroundStyle(.primary)
        .fixedSize(horizontal: true, vertical: true)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private struct BudgetLinkButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.5 : 1)
        }
    }

    private struct MetricButtonStyle: ButtonStyle {
        var highlightPadding: CGFloat = 0
        var highlightCornerRadius: CGFloat = AppRadius.small

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: highlightCornerRadius)
                        .fill(AppColor.controlFill)
                        // Outset only the decoration; the label and hit area keep their bounds.
                        .padding(-highlightPadding)
                        .opacity(configuration.isPressed ? 1 : 0)
                        .allowsHitTesting(false)
                }
        }
    }

    private var stackedHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            headline
            headerAccessory
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
            Text(headlineTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(money(headlineAmount, signed: showsMetrics && !insights.hasBudget))
                .font(.system(size: amountSize, weight: .semibold))
                .foregroundStyle(!showsMetrics && (insights.remaining ?? 0) < 0 ? BudgetStatus.overLimit.tint : .primary)
                .monospacedDigit()
                .modifier(DashboardNumericAmount(amount: headlineAmount))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headlineTitle)
        .accessibilityValue(spoken(headlineAmount))
    }

    private var headlineTitle: String {
        if insights.hasBudget {
            return !showsMetrics && (insights.remaining ?? 0) < 0 ? "Over budget" : "Budget left"
        }
        return showsMetrics ? "Net" : spendingTitle
    }

    private var headlineAmount: Decimal {
        if let remaining = insights.remaining, insights.hasBudget {
            return showsMetrics ? remaining : abs(remaining)
        }
        return showsMetrics ? insights.net : insights.spent
    }

    @ViewBuilder
    private var trend: some View {
        if let percent = insights.comparisonPercent {
            let color = percent < 0 ? AppColor.positiveText : percent > 0 ? AppColor.destructiveText : Color.secondary
            HStack(spacing: AppSpacing.extraSmall) {
                if percent != 0 {
                    AppIcon(percent < 0 ? "trade-down" : "trade-up", size: 14, relativeTo: .footnote)
                }
                Text(trendText(percent))
                    .font(.footnote.weight(.medium))
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
