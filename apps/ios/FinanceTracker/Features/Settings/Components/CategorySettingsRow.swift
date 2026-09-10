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
        .circleSwipeActions {
            if !category.isSystem {
                CircleSwipeAction(title: "Delete", icon: "trash", action: onDelete)
            }
            CircleSwipeAction(title: "Edit", icon: "edit-pencil", tint: .gray, action: onEdit)
        }
    }
}
