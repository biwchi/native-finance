import SwiftUI

struct BudgetAttentionRow: View {
    let item: BudgetOverviewData.Attention
    let currency: String
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            AppIcon("warning-triangle", size: 23)
                .foregroundStyle(BudgetStatus.overLimit.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                Text(item.progress.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(MoneyFormatter.format(abs(item.progress.remaining), currency: currency, roundToWhole: roundTotals)) over \(item.isPool ? "pool" : "category") limit")
                    .font(.caption)
                    .foregroundStyle(BudgetStatus.overLimit.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppSpacing.extraSmall)
        .accessibilityElement(children: .combine)
    }
}
