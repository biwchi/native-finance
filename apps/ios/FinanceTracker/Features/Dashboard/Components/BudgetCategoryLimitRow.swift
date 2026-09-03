import SwiftUI

struct BudgetCategoryLimitRow: View {
    let category: TransactionCategory?
    let categoryName: String
    let groupName: String?
    let formattedLimit: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            if let category {
                CategoryIcon(category: category, size: 38)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(categoryName)
                    .foregroundStyle(.primary)
                if let groupName {
                    Text(groupName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(formattedLimit)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
