import SwiftUI

struct CategoryListRow: View {
    enum Accessory {
        case disclosure
        case checkmark(isSelected: Bool)
    }

    let category: TransactionCategory
    var isSubcategory = false
    var subtitle: String? = nil
    var accessory: Accessory = .disclosure

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            if isSubcategory {
                AppIcon("arrow-right", size: 20)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }

            CategoryIcon(category: category)
            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                Text(category.name)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: AppSpacing.small)

            switch accessory {
            case .disclosure:
                AppIcon("nav-arrow-right", size: 20)
                    .foregroundStyle(.secondary)
            case .checkmark(let isSelected):
                AccentSelectionButton.Indicator(isSelected: isSelected)
                    .transaction { $0.animation = nil }
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: AppControlSize.minimumTapTarget)
        .contentShape(Rectangle())
    }
}
