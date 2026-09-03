import SwiftUI

struct TransactionRow: View {
    enum Style {
        case transaction
        case upcoming
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let transaction: any EditableTransaction
    let account: Account?
    var titleOverride: String? = nil
    var recurrenceDetails: String? = nil
    var style: Style = .transaction

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            transactionIcon

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    details
                    amount
                }
            } else {
                details
                Spacer(minLength: AppSpacing.medium)
                amount
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
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            if style == .transaction {
                accountLabel
            }

            if let recurrenceDetails {
                Text(recurrenceDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private var title: String {
        titleOverride ?? transaction.category?.name ?? "Uncategorized"
    }

    private var amountText: String {
        transaction.formattedAmount(showExpenseSign: style == .transaction)
    }

    private var accessibilityDescription: String {
        let date = transaction.occurredAt.formatted(date: .abbreviated, time: .shortened)
        let recurrence = transaction.recurrence.map {
            ", recurring \($0.frequency.title.lowercased())"
        } ?? ""
        let accountDetails = style == .transaction ? ", \(account?.name ?? "Unknown account")" : ""
        return "\(title)\(accountDetails), \(amountText), \(date)\(recurrence)"
    }

    private var iconColor: Color {
        transaction.kind == .income ? AppColor.positive : AppColor.accent
    }
}
