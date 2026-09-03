import SwiftUI

struct QuickAccountMenu: View {
    let accounts: [Account]
    let selectedAccountID: UUID?
    let onSelect: (UUID) -> Void

    private var title: String {
        accounts.first { $0.id == selectedAccountID }?.name ?? "Account"
    }

    var body: some View {
        Menu {
            ForEach(accounts) { account in
                Button {
                    onSelect(account.id)
                } label: {
                    Label(account.name, icon: account.icon)
                }
            }
        } label: {
            HStack(spacing: 5) {
                AppIcon("credit-card")
                Text(title)
                    .lineLimit(1)
                AppIcon("nav-arrow-down", size: 11)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .frame(height: 38)
            .modifier(CapsuleControlBackground())
        }
        .buttonStyle(.plain)
        .disabled(accounts.isEmpty)
        .accessibilityLabel("Account, \(title)")
    }
}
