import SwiftUI

struct MonthlySummaryCard<Accessory: View, Content: View>: View {
    let monthTitle: String
    var titleColor: Color = .primary
    var surface: FinanceCardSurface = .standard
    var gradientTint: Color? = nil
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.monthlySummaryCardBackground) private var cardBackground

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            MonthlySummaryRow {
                Text(monthTitle)
                    .foregroundStyle(titleColor)
            } trailing: {
                accessory
            }
            .font(.subheadline.weight(.regular))

            content
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, AppSpacing.extraLarge)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? AppSpacing.large : 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if let gradientTint {
                RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [gradientTint.opacity(0.14), gradientTint.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .financeCardSurface(
            surface,
            fallbackColor: cardBackground,
            cornerRadius: AppRadius.extraLarge
        )
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous))
    }
}
