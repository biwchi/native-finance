import SwiftUI

struct TransactionMetadataBar: View {
    let accounts: [Account]
    let selectedAccountID: UUID?
    @Binding var date: Date
    let hasExtraDetails: Bool
    let onSelectAccount: (UUID) -> Void

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            QuickAccountMenu(
                accounts: accounts,
                selectedAccountID: selectedAccountID,
                onSelect: onSelectAccount
            )

            DatePicker(
                "Date and time",
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .fixedSize()

            NavigationLink(value: AddTransactionRoute.details) {
                AppIcon(hasExtraDetails ? "clipboard-check" : "page-plus", size: 17)
                    .frame(width: 38, height: 38)
                    .modifier(CapsuleControlBackground())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Transaction details")
        }
        .frame(maxWidth: .infinity)
    }
}
