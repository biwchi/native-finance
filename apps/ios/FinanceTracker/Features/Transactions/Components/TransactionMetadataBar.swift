import SwiftUI

struct TransactionMetadataBar: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isEditingDate = false

    let accounts: [Account]
    let selectedAccountID: UUID?
    let accountBalance: String
    @Binding var date: Date
    let hasExtraDetails: Bool
    let onSelectAccount: (UUID) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: AppSpacing.small) {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        accountMenu
                        dateTimeButton
                    }
                    Spacer(minLength: 0)
                    detailsLink
                }
            } else {
                HStack(spacing: AppSpacing.small) {
                    accountMenu
                    dateTimeButton
                    Spacer(minLength: 0)
                    detailsLink
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var accountMenu: some View {
        AccountPickerMenu(
            accounts: accounts,
            selectedAccountID: selectedAccountID,
            subtitle: accountBalance,
            onSelect: onSelectAccount
        )
    }

    private var dateTimeButton: some View {
        Button {
            isEditingDate = true
        } label: {
            HStack(spacing: AppSpacing.small) {
                AppIcon("calendar", size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(calendar.isDateInToday(date) ? "Today" : date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.subheadline.weight(.semibold))
                    Text(date, format: .dateTime.hour().minute())
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(minHeight: AppControlSize.minimumTapTarget)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.extraSmall)
            .contentShape(Capsule())
            .modifier(TransactionGlassSurface(shape: Capsule(), isInteractive: true))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Transaction date and time")
        .accessibilityValue(date.formatted(date: .complete, time: .shortened))
        .popover(isPresented: $isEditingDate) {
            DatePickerPopover(title: "Date & time", selection: $date, components: [.date, .hourAndMinute]) {
                isEditingDate = false
            }
        }
    }

    private var detailsLink: some View {
        NavigationLink(value: AddTransactionRoute.details) {
            AppIcon(hasExtraDetails ? "clipboard-check" : "page-plus", size: 22)
                .foregroundStyle(.primary)
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                .padding(AppSpacing.extraSmall)
                .contentShape(Circle())
                .modifier(TransactionGlassSurface(shape: Circle(), isInteractive: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Transaction details")
        .accessibilityValue(hasExtraDetails ? "Details added" : "No extra details")
    }

}
