import SwiftUI

struct DashboardSummaryMetrics: View {
    let insights: DashboardInsights
    let currency: String
    var isInteractive = false

    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled

    enum Metric: String, CaseIterable, Identifiable {
        case net, income, spent

        var id: String { rawValue }
        var title: String {
            switch self {
            case .net: String(localized: "Net")
            case .income: String(localized: "Income")
            case .spent: String(localized: "Spent")
            }
        }
        var icon: String {
            switch self {
            case .net: "equal"
            case .income: "arrow-down-left"
            case .spent: "arrow-up-right"
            }
        }
        var iconColor: Color {
            switch self {
            case .net: AppColor.blueIcon
            case .income: AppColor.tealIcon
            case .spent: AppColor.orangeIcon
            }
        }
        func amount(in insights: DashboardInsights) -> Decimal {
            switch self {
            case .net: insights.net
            case .income: insights.income
            case .spent: insights.spent
            }
        }
    }

    struct BoundsKey: PreferenceKey {
        static let defaultValue: [Metric: [Anchor<CGRect>]] = [:]

        static func reduce(value: inout [Metric: [Anchor<CGRect>]], nextValue: () -> [Metric: [Anchor<CGRect>]]) {
            value.merge(nextValue(), uniquingKeysWith: +)
        }
    }

    private var metrics: [Metric] { insights.hasBudget ? [.net, .income, .spent] : [.income, .spent] }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedMetrics
            } else {
                ViewThatFits(in: .horizontal) {
                    columns()
                    columns(compactDigits: 3)
                    columns(compactDigits: 2)
                    // Large text or unusually long currency symbols can still need more room.
                    stackedMetrics
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func columns(compactDigits: Int? = nil) -> some View {
        MetricsLayout(count: metrics.count) {
            ForEach(metrics) { metric in
                label(metric)
            }
            ForEach(metrics) { metric in
                amount(metric, compactDigits: compactDigits)
            }
        }
    }

    private var stackedMetrics: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    label(metric)
                    ViewThatFits(in: .horizontal) {
                        amount(metric).fixedSize()
                        amount(metric, compactDigits: 3).fixedSize()
                        ScrollView(.horizontal) { amount(metric).fixedSize() }
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ metric: Metric) -> some View {
        HStack(spacing: AppSpacing.compact) {
            AppIcon(metric.icon, size: 14, relativeTo: .subheadline)
                .foregroundStyle(metric.iconColor)
            Text(metric.title)
                .font(.subheadline.weight(metric == .net ? .medium : .regular))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .anchorPreference(key: BoundsKey.self, value: .bounds) { [metric: [$0]] }
        .accessibilityHidden(true)
    }

    private func amount(_ metric: Metric, compactDigits: Int? = nil) -> some View {
        let value = metric.amount(in: insights)
        let text = compactDigits.map {
            MoneyFormatter.compact(value, currency: currency, showPositiveSign: metric == .net,
                                   roundToWhole: roundTotals, significantDigits: $0)
        } ?? MoneyFormatter.format(value, currency: currency, showPositiveSign: metric == .net,
                                   roundToWhole: roundTotals)
        return Text(text)
            .font(.body.weight(metric == .net ? .semibold : .medium))
            .foregroundStyle(metric == .net && value != 0
                             ? (value > 0 ? AppColor.positiveText : AppColor.destructiveText) : .primary)
            .monospacedDigit()
            .modifier(DashboardNumericAmount(amount: value))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .anchorPreference(key: BoundsKey.self, value: .bounds) { [metric: [$0]] }
            .accessibilityLabel(metric.title)
            .accessibilityValue(MoneyFormatter.spoken(value, currency: currency, locale: locale))
            .accessibilityHidden(isInteractive)
    }

    /// Equal-width columns keep labels, amounts, and touch targets on the same grid.
    struct MetricsLayout: Layout {
        let count: Int

        private struct Measurement {
            let labels: [ViewDimensions]
            let amounts: [ViewDimensions]
            let minimumColumnWidth: CGFloat
            let labelHeight: CGFloat
            let ascent: CGFloat
            let descent: CGFloat
            var height: CGFloat { labelHeight + AppSpacing.small + ascent + descent }
        }

        private func measure(_ subviews: Subviews) -> Measurement {
            let labels = (0..<count).map { subviews[$0].dimensions(in: .unspecified) }
            let amounts = (0..<count).map { subviews[count + $0].dimensions(in: .unspecified) }
            return Measurement(
                labels: labels, amounts: amounts,
                minimumColumnWidth: (labels + amounts).map(\.width).max() ?? 0,
                labelHeight: labels.map(\.height).max() ?? 0,
                ascent: amounts.map { $0[.firstTextBaseline] }.max() ?? 0,
                descent: amounts.map { $0.height - $0[.firstTextBaseline] }.max() ?? 0
            )
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let measured = measure(subviews)
            let minimum = measured.minimumColumnWidth * CGFloat(count) + CGFloat(count - 1) * AppSpacing.large
            let proposed = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minimum
            return CGSize(width: max(proposed, minimum), height: measured.height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let measured = measure(subviews)
            let columnWidth = (bounds.width - CGFloat(count - 1) * AppSpacing.large) / CGFloat(count)
            func place(_ index: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
                // SwiftUI mirrors these logical coordinates for right-to-left environments.
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: width, height: height))
            }
            for index in 0..<count {
                let x = CGFloat(index) * (columnWidth + AppSpacing.large)
                let label = measured.labels[index]
                let amount = measured.amounts[index]
                place(index, x: x, y: (measured.labelHeight - label.height) / 2,
                      width: columnWidth, height: label.height)
                place(count + index, x: x,
                      y: measured.labelHeight + AppSpacing.small + measured.ascent - amount[.firstTextBaseline],
                      width: columnWidth, height: amount.height)
            }
        }
    }

    struct Detail: View {
        let metric: Metric
        let amount: Decimal
        let currency: String
        @Environment(\.dismiss) private var dismiss
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.locale) private var locale

        var body: some View {
            NavigationStack {
                ScrollView {
                    ScrollView(.horizontal) {
                        Text(MoneyFormatter.format(amount, currency: currency, showPositiveSign: metric == .net))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .fixedSize()
                            .textSelection(.enabled)
                            .accessibilityLabel(MoneyFormatter.spoken(amount, currency: currency, locale: locale))
                    }
                    .padding(AppSpacing.doubleExtraLarge)
                }
                .scrollEdgeFades()
                .navigationTitle(metric.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Group {
                            Button("Done") { dismiss() }
                        }
                        .legacyToolbarControl()
                    }
                }
            }
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.medium, .large] : [.height(180), .medium])
            .presentationDragIndicator(.visible)
            .legacySheetAppearance()
        }
    }
}
