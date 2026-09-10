import SwiftUI

struct TransactionMetadataBar: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconBadgeSize = 36
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
        Menu {
            Picker("Account", selection: Binding(
                get: { selectedAccountID },
                set: { if let accountID = $0 { onSelectAccount(accountID) } }
            )) {
                ForEach(accounts) { account in
                    Label(account.name, icon: account.icon).tag(Optional(account.id))
                }
            }
        } label: {
            HStack(spacing: AppSpacing.small) {
                AppIcon(selectedAccount?.icon ?? "credit-card", size: 22)
                    .foregroundStyle(AppColor.iconForeground(for: accountColor))
                    .frame(width: iconBadgeSize, height: iconBadgeSize)
                    .background(accountColor.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(selectedAccount?.name ?? "Account")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(accountBalance)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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
        .disabled(accounts.isEmpty)
        .accessibilityLabel("Account, \(selectedAccount?.name ?? "Choose account")")
        .accessibilityValue(accountBalance)
        .accessibilityHint("Opens the account picker")
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
            VStack(spacing: AppSpacing.medium) {
                HStack {
                    Text("Date & time").font(.headline)
                    Spacer()
                    Button("Done") { isEditingDate = false }
                }
                DatePicker("Transaction date and time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
            }
            .padding(AppSpacing.large)
            .frame(minWidth: 300, idealWidth: 340)
            .presentationCompactAdaptation(.popover)
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

    private var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountID }
    }

    private var accountColor: Color {
        selectedAccount?.iconColor.color ?? .secondary
    }
}
