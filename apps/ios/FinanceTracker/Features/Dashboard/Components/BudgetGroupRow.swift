import SwiftUI

struct BudgetGroupRow: View {
    let name: String
    let formattedLimit: String
    let tint: Color

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            AppIcon("credit-cards", size: 17)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.small))

            Text(name.isEmpty ? "Untitled pool" : name)
                .foregroundStyle(.primary)

            Spacer()

            Text(formattedLimit)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
