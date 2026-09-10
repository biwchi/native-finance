import SwiftUI

struct BudgetLimitRow<Icon: View>: View {
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @Environment(\.locale) private var locale
    let name: String
    let spent: Decimal
    let limit: Decimal?
    let currency: String
    var tint: Color = AppColor.accent
    var context: String? = nil
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            icon
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                header
                if let limit, limit > 0 {
                    BudgetProgressBar(
                        budgetProgress: NSDecimalNumber(decimal: spent / limit).doubleValue,
                        monthProgress: nil,
                        tint: isOverBudget ? BudgetStatus.overLimit.tint : tint,
                        isCompact: true
                    )
                }
                if let context {
                    Text(context)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, AppSpacing.compact)
        .frame(minHeight: 38, alignment: .center)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(accessibilityValue + (context.map { ". \($0)" } ?? ""))
    }

    private var remaining: Decimal? { limit.flatMap { $0 > 0 ? $0 - spent : nil } }
    private var isOverBudget: Bool { (remaining ?? 0) < 0 }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.medium) {
                VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                    title
                    usage
                }
                .fixedSize()
                Spacer(minLength: 0)
                amount(alignment: .trailing).fixedSize()
            }
            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                title
                amount(alignment: .leading)
                usage
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var title: some View {
        Text(name)
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var usage: some View {
        if let limit, limit > 0 {
            Text("\(money(spent)) / \(money(limit))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func amount(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: AppSpacing.extraSmall) {
            Text(money(remaining.map { abs($0) } ?? spent))
                .font(.headline)
                .foregroundStyle(isOverBudget ? BudgetStatus.overLimit.tint : .primary)
                .monospacedDigit()
            if remaining != nil {
                Text(isOverBudget ? "over budget" : "left")
                    .font(.caption)
                    .foregroundStyle(isOverBudget ? BudgetStatus.overLimit.tint : .secondary)
            }
        }
    }

    private var accessibilityValue: String {
        guard let remaining, let limit else { return "\(spoken(spent)) spent" }
        return "\(spoken(abs(remaining))) \(isOverBudget ? "over budget" : "left"), \(spoken(spent)) of \(spoken(limit)) spent"
    }

    private func spoken(_ amount: Decimal) -> String {
        MoneyFormatter.spoken(amount, currency: currency, locale: locale, roundToWhole: roundTotals)
    }

    private func money(_ amount: Decimal) -> String {
        MoneyFormatter.format(amount, currency: currency, roundToWhole: roundTotals)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}
