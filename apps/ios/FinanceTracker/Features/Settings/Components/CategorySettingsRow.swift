import SwiftUI

struct CategorySettingsRow: View {
    let category: TransactionCategory
    var isSubcategory = false
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            CategoryListRow(category: category, isSubcategory: isSubcategory)
        }
        .buttonStyle(.plain)
        .circleSwipeActions {
            if !category.isSystem {
                CircleSwipeAction(title: "Delete", icon: "trash", action: onDelete)
            }
            CircleSwipeAction(title: "Edit", icon: "edit-pencil", tint: AppColor.informative, action: onEdit)
        }
    }
}
