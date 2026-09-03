import SwiftUI

struct CategorySettingsRow: View {
    let category: TransactionCategory
    var isSubcategory = false
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: AppSpacing.medium) {
                if isSubcategory {
                    AppIcon("arrow-right", size: 12)
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                }

                CategoryIcon(category: category)
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                AppIcon("nav-arrow-right", size: 12)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !category.isSystem {
                Button("Delete", role: .destructive, action: onDelete)
            }

            Button("Edit", action: onEdit)
                .tint(.gray)
        }
    }
}
