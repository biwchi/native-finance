import SwiftUI

struct BudgetPoolHeader: View {
    let progress: BudgetLimitProgress
    let categoryCount: Int
    let iconName: String
    let tint: Color
    let monthProgress: Double?
    let isExpanded: Bool
    let currency: String

    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                AppIcon(iconName, size: 21)
                    .foregroundStyle(AppColor.iconForeground(for: tint))
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.medium))
                MonthlySummaryRow {
                    VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                        Text(progress.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(categoryCount) \(categoryCount == 1 ? "category" : "categories")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } trailing: {
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: AppSpacing.extraSmall) {
                        Text(money(abs(progress.remaining)))
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(progress.remaining < 0 ? BudgetStatus.overLimit.tint : .primary)
                        Text(progress.remaining < 0 ? "over budget" : "left")
                            .font(.caption)
                            .foregroundStyle(progress.remaining < 0 ? BudgetStatus.overLimit.tint : .secondary)
                    }
                }
                AppIcon("nav-arrow-down", size: 14)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .foregroundStyle(.secondary)
                    .padding(.top, AppSpacing.extraSmall)
            }

            BudgetProgressBar(
                budgetProgress: progress.progress, monthProgress: monthProgress,
                tint: progress.remaining < 0 ? BudgetStatus.overLimit.tint : AppColor.iconForeground(for: tint)
            )

            Text("\(money(progress.spent)) of \(money(progress.limit)) spent")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppSpacing.extraSmall)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isExpanded ? "Collapse categories" : "Expand categories")
    }

    private var accessibilityValue: String {
        let remaining = MoneyFormatter.spoken(abs(progress.remaining), currency: currency, locale: locale, roundToWhole: roundTotals)
        let spent = MoneyFormatter.spoken(progress.spent, currency: currency, locale: locale, roundToWhole: roundTotals)
        let limit = MoneyFormatter.spoken(progress.limit, currency: currency, locale: locale, roundToWhole: roundTotals)
        let pace = monthProgress.map { ", \($0.formatted(.percent.precision(.fractionLength(0)).locale(locale))) of month elapsed" } ?? ""
        return "\(remaining) \(progress.remaining < 0 ? "over budget" : "left"), \(spent) of \(limit) spent\(pace), \(isExpanded ? "expanded" : "collapsed")"
    }

    private func money(_ amount: Decimal) -> String {
        MoneyFormatter.format(amount, currency: currency, roundToWhole: roundTotals)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}
