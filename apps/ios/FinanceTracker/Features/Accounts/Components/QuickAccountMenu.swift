import SwiftUI

struct QuickAccountMenu: View {
    let accounts: [Account]
    let selectedAccountID: UUID?
    var appearance: CapsuleControlBackground.Appearance = .filled
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
            .frame(minHeight: appearance == .glass ? AppControlSize.minimumTapTarget : 38)
            .modifier(CapsuleControlBackground(appearance: appearance))
        }
        .buttonStyle(.plain)
        .disabled(accounts.isEmpty)
        .accessibilityLabel("Account, \(title)")
    }
}

struct AccountPickerMenu: View {
    let accounts: [Account]
    let selectedAccountID: UUID?
    let subtitle: String?
    var onManageAccounts: (() -> Void)? = nil
    let onSelect: (UUID) -> Void

    private var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountID }
    }

    var body: some View {
        Menu {
            if !accounts.isEmpty {
                Picker("Account", selection: Binding(
                    get: { selectedAccountID },
                    set: { if let accountID = $0 { onSelect(accountID) } }
                )) {
                    ForEach(accounts) { account in
                        Label(account.name, icon: account.icon).tag(Optional(account.id))
                    }
                }
            }
            if let onManageAccounts {
                if !accounts.isEmpty { Divider() }
                Button(action: onManageAccounts) {
                    Label("View Accounts", icon: "list")
                }
            }
        } label: {
            HStack(spacing: AppSpacing.small) {
                AccountIconBadge(
                    iconName: selectedAccount?.icon ?? "credit-card",
                    color: selectedAccount?.iconColor.color ?? .secondary,
                    iconSize: 22
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(selectedAccount?.name ?? "Account")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .frame(minHeight: AppControlSize.minimumTapTarget, alignment: .leading)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.extraSmall)
            .contentShape(Capsule())
            .modifier(TransactionGlassSurface(shape: Capsule(), isInteractive: true))
        }
        .buttonStyle(.plain)
        .disabled(accounts.isEmpty && onManageAccounts == nil)
        .accessibilityLabel("Account, \(selectedAccount?.name ?? "Choose account")")
        .accessibilityValue(subtitle ?? "")
        .accessibilityHint("Opens the account picker")
    }
}
