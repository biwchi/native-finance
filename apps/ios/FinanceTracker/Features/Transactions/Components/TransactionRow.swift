import SwiftUI

struct TransactionRow: View {
    enum Style {
        case transaction
        case upcoming
    }

    enum TimestampStyle {
        case time
        case dateAndTime
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let transaction: any EditableTransaction
    let account: Account?
    var titleOverride: String? = nil
    var recurrenceDetails: String? = nil
    var secondaryAmountText: String? = nil
    var style: Style = .transaction
    var timestampStyle: TimestampStyle = .time

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            transactionIcon

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    details
                    amountDetails
                }
            } else if style == .transaction {
                transactionDetails
            } else {
                details
                Spacer(minLength: AppSpacing.medium)
                amountDetails
                    .layoutPriority(1)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + 54
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var transactionIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let category = transaction.category {
                    CategoryIcon(category: category, size: 42)
                } else {
                    AppIcon(transaction.kind == .income ? "arrow-down-left" : "arrow-up-right", size: 18)
                        .foregroundStyle(iconColor)
                        .frame(width: 42, height: 42)
                        .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.medium))
                }
            }

            if style == .transaction, transaction.recurrence != nil {
                AppIcon("repeat", size: 8)
                    .foregroundStyle(Color.primary)
                    .frame(width: 16, height: 16)
                    .background(.regularMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(AppColor.separator, lineWidth: 0.5)
                    }
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 45, height: 45, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            titleLabel

            if style == .transaction {
                timestampLabel
            }

            if let recurrenceDetails {
                Text(recurrenceDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transactionDetails: some View {
        Grid(alignment: .leading, verticalSpacing: 5) {
            GridRow {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.medium) {
                    titleLabel
                    Spacer(minLength: AppSpacing.medium)
                    amount
                }
            }

            GridRow {
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    timestampLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                    transactionMetadata
                        .layoutPriority(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var titleLabel: some View {
        Text(title)
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }

    private var timestampLabel: some View {
        Text(timestampText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(noteText == nil ? 1 : 4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var amountDetails: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 5) {
            amountWithSecondary

            if style == .transaction {
                accountLabel
            }
        }
    }

    private var transactionMetadata: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let secondaryAmountText {
                secondaryAmountLabel(secondaryAmountText)
            }

            accountLabel
        }
    }

    private var accountLabel: some View {
        HStack(spacing: 5) {
            AppIcon(account?.icon ?? "credit-card", size: 11)
                .foregroundStyle(account?.iconColor.color ?? Color.secondary)
                .accessibilityHidden(true)

            Text(account?.name ?? "Unknown account")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
    }

    private var amount: some View {
        Text(amountText)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(transaction.kind == .income ? AppColor.positive : .primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var amountWithSecondary: some View {
        VStack(
            alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing,
            spacing: 2
        ) {
            amount

            if let secondaryAmountText {
                secondaryAmountLabel(secondaryAmountText)
            }
        }
    }

    private func secondaryAmountLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.regular))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var title: String {
        titleOverride ?? transaction.category?.name ?? "Uncategorized"
    }

    private var amountText: String {
        transaction.formattedAmount(showExpenseSign: style == .transaction)
    }

    private var timestampText: String {
        if let noteText {
            return noteText
        }

        switch timestampStyle {
        case .time:
            return transaction.occurredAt.formatted(date: .omitted, time: .shortened)
        case .dateAndTime:
            return transaction.occurredAt.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private var accessibilityDescription: String {
        let date = transaction.occurredAt.formatted(date: .abbreviated, time: .shortened)
        let recurrence = transaction.recurrence.map {
            ", recurring \($0.frequency.title.lowercased())"
        } ?? ""
        let accountDetails = style == .transaction ? ", \(account?.name ?? "Unknown account")" : ""
        let original = secondaryAmountText.map { ", originally \($0)" } ?? ""
        return "\(title)\(accountDetails), \(amountText)\(original), \(noteText ?? date)\(recurrence)"
    }

    private var noteText: String? {
        guard let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return nil }
        return note
    }

    private var iconColor: Color {
        transaction.kind == .income ? AppColor.positive : AppColor.accent
    }
}
