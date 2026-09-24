import SwiftUI

struct AccountManagementRow: View {
    let account: Account
    let balanceSubtitle: String
    let isWorking: Bool
    let isSelected: Bool
    let isEditing: Bool

    var body: some View {
        HStack(spacing: 12) {
            AccountIconBadge(iconName: account.icon, color: account.iconColor.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .foregroundStyle(.primary)

                Text(balanceSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            if isEditing {
                AppIcon("nav-arrow-right", size: 12)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            } else if isSelected {
                AppIcon("check", size: 17)
                    .foregroundStyle(AppColor.accent)
                    .accessibilityHidden(true)
            }
        }
    }
}
