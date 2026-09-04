import SwiftUI
#if canImport(UIKit)
import UIKit
#endif


struct AccountSelector: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    // The picker needs all currencies even when the dashboard is showing one account.
    @StateObject private var exchangeRateStore = ExchangeRateStore()
    @ScaledMetric(relativeTo: .body) private var iconBadgeSize = 36

    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var reportingCurrency = AppPreferences.initialCurrency

    var compact = false

    var body: some View {
        Menu {
            Toggle(isOn: accountSelection(nil)) {
                accountLabel(
                    title: "All Accounts",
                    subtitle: balanceSubtitle(for: nil, includesLabel: false),
                    iconName: "credit-cards",
                    color: AppColor.accent
                )
            }

            if !accountStore.accounts.isEmpty {
                Divider()

                ForEach(accountStore.accounts) { account in
                    Toggle(isOn: accountSelection(account.id)) {
                        accountLabel(
                            title: account.name,
                            subtitle: balanceSubtitle(for: account, includesLabel: false),
                            iconName: account.icon,
                            color: account.iconColor.color
                        )
                    }
                }
            }

            Divider()

            Button {
                accountStore.isManagingAccounts = true
            } label: {
                Label("Manage Accounts", icon: "settings")
            }
        } label: {
            selectorLabel
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Account, \(accountStore.selectionTitle), \(selectionSubtitle)")
                .accessibilityHint("Opens the account picker")
        }
        .buttonStyle(.plain)
        .tint(AppColor.accent)
        .task(id: exchangeRateScopeKey) {
            await exchangeRateStore.load(
                currencies: exchangeCurrencies,
                reportingCurrency: reportingCurrency.uppercased()
            )
        }
    }

    @ViewBuilder
    private var selectorLabel: some View {
        if compact {
            HStack(spacing: 9) {
                selectedIconBadge

                VStack(alignment: .leading, spacing: 0) {
                    Text(accountStore.selectionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text(selectionSubtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding([.leading, .vertical], 4)
            .padding(.trailing, 12)
            .accountSelectorGlass()
            .contentShape(Capsule())
        } else {
            HStack(spacing: 9) {
                selectedIconBadge

                VStack(alignment: .leading, spacing: 0) {
                    Text(accountStore.selectionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text(selectionSubtitle)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .layoutPriority(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 14)
            .padding(.vertical, 5)
            .accountSelectorGlass()
            .contentShape(Capsule())
        }
    }

    private var selectedIcon: String {
        accountStore.selectedAccount?.icon ?? "credit-cards"
    }

    private var selectedColor: Color {
        accountStore.selectedAccount?.iconColor.color ?? AppColor.accent
    }

    private var selectedIconBadge: some View {
        AppIcon(selectedIcon, size: 24)
            .foregroundStyle(selectedColor)
            .frame(width: iconBadgeSize, height: iconBadgeSize)
            .background(selectedColor.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }

    private var selectionSubtitle: String {
        balanceSubtitle(for: accountStore.selectedAccount)
    }

    private func balanceSubtitle(for account: Account?, includesLabel: Bool = true) -> String {
        switch transactionStore.state {
        case .idle, .loading:
            "Loading balance"
        case .loaded:
            if let balance = transactionStore.balance(
                accountID: account?.id,
                currency: account?.currency ?? reportingCurrency.uppercased(),
                rates: exchangeRateStore.snapshot
            ) {
                MoneyFormatter.format(
                    balance, currency: account?.currency ?? reportingCurrency.uppercased()
                ) + (includesLabel ? " balance" : "")
            } else if exchangeRateStore.state == .idle || exchangeRateStore.state == .loading {
                "Converting balance"
            } else {
                "Balance unavailable"
            }
        case .failed:
            "Balance unavailable"
        }
    }

    private var exchangeCurrencies: Set<String> {
        return Set(
            accountStore.accounts.map(\.currency) +
            transactionStore.allTransactions.map(\.currency)
        )
    }

    private var exchangeRateScopeKey: String {
        "\(reportingCurrency.uppercased()):\(exchangeCurrencies.sorted().joined(separator: ","))"
    }

    private func accountSelection(_ accountID: UUID?) -> Binding<Bool> {
        Binding(
            get: { accountStore.selectedAccountID == accountID },
            set: { isSelected in
                if isSelected { accountStore.selectedAccountID = accountID }
            }
        )
    }

    @ViewBuilder
    private func accountLabel(
        title: String,
        subtitle: String,
        iconName: String,
        color: Color? = nil
    ) -> some View {
        Text(title)
        Text(subtitle)
        menuIcon(iconName: iconName, color: color)
    }

    @ViewBuilder
    private func menuIcon(iconName: String, color: Color?) -> some View {
#if canImport(UIKit)
        if let color, let image = AppIcons.uiImage(named: iconName) {
            Image(
                uiImage: image.withTintColor(
                    UIColor(color),
                    renderingMode: .alwaysOriginal
                )
            )
        } else {
            AppIcons.resolve(iconName).image().renderingMode(.template)
                .foregroundStyle(.primary)
        }
#else
        AppIcon(iconName)
            .foregroundStyle(color ?? .primary)
#endif
    }
}
