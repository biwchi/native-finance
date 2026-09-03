import SwiftUI

struct CategorySelectionRow: View {
    let category: TransactionCategory
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            CategoryIcon(category: category)
            Text(title)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AppSpacing.small)
            if isSelected {
                AppIcon("check", size: 17)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, AppSpacing.extraSmall)
        .contentShape(Rectangle())
    }
}
