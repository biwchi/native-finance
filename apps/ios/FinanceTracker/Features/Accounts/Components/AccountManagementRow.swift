import SwiftUI

struct AccountManagementRow: View {
    let account: Account
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(account.icon, size: 17)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(account.iconColor.color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .foregroundStyle(.primary)

                Text("\(account.type.title) · \(account.currency)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isWorking {
                ProgressView()
            } else {
                AppIcon("nav-arrow-right", size: 12)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
