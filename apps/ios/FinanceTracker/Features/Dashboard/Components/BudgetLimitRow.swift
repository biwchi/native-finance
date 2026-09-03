import SwiftUI

struct BudgetLimitRow: View {
    let progress: BudgetLimitProgress
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            MonthlySummaryRow {
                Text(progress.name).font(.body.weight(.medium))
            } trailing: {
                Text("\(money(progress.spent)) / \(money(progress.limit))")
                    .font(.subheadline).monospacedDigit()
            }
            BudgetProgressBar(budgetProgress: progress.progress, monthProgress: nil,
                              tint: progress.remaining < 0 ? BudgetStatus.overLimit.tint : AppColor.accent)
            Text("\(money(abs(progress.remaining))) \(progress.remaining < 0 ? "over" : "left")")
                .font(.footnote)
                .foregroundStyle(progress.remaining < 0 ? BudgetStatus.overLimit.tint : .secondary)
                .monospacedDigit()
        }
        .padding(.vertical, AppSpacing.compact)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func money(_ amount: Decimal) -> String { MoneyFormatter.format(amount, currency: currency) }
}
