import SwiftUI

struct AccountManagementRow: View {
    let account: Account
    let balanceSubtitle: String
    let isWorking: Bool
    let isSelected: Bool
    let isEditing: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(account.icon, size: 17)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(account.iconColor.color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .foregroundStyle(.primary)

                Text(balanceSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            if isWorking {
                ProgressView()
            } else if isEditing {
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
