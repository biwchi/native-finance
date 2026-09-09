import SwiftUI

struct DashboardUpcomingReminder: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let transaction: UpcomingTransaction
    let count: Int
    var now: Date = .now

    private var layers: Int { min(max(count - 1, 0), 2) }
    private var title: String {
        let counterparty = transaction.kind == .income ? transaction.payee : transaction.merchant
        return [counterparty, transaction.category?.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Uncategorized"
    }
    private var noteOrTime: String {
        if let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return note
        }
        return transaction.occurredAt.formatted(date: .omitted, time: .shortened)
    }
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.medium))
            : AnyLayout(HStackLayout(spacing: AppSpacing.medium))
    }
    private var dueText: String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: transaction.occurredAt)).day ?? 0
        switch days {
        case 0: return "Coming up today"
        case 1: return "Coming up tomorrow"
        default: return "Coming up in \(days) days"
        }
    }

    var body: some View {
        layout {
            transactionIcon
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    details
                    amountWithChevron
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                details
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                amountWithChevron
                    .fixedSize()
            }
        }
        .padding(AppSpacing.medium)
        .background {
            ZStack {
                if layers > 0 {
                    ForEach((1...layers).reversed(), id: \.self) { layer in
                        surface
                            .padding(.horizontal, CGFloat(layer) * 10)
                            .offset(y: CGFloat(layer) * 7)
                    }
                }
                surface
            }
        }
        .padding(.bottom, CGFloat(layers) * 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dueText), \(title), \(noteOrTime), \(transaction.formattedAmount())")
        .accessibilityValue(count > 1 ? "\(count) upcoming recurring transactions" : "")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
            Text(dueText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(title) · \(noteOrTime)")
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var transactionIcon: some View {
        Group {
            if let category = transaction.category {
                CategoryIcon(category: category, size: 42)
            } else {
                let color = transaction.kind == .income ? AppColor.positive : AppColor.accent
                AppIcon(transaction.kind == .income ? "arrow-down-left" : "arrow-up-right", size: 18)
                    .foregroundStyle(AppColor.iconForeground(for: color))
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.medium))
            }
        }
        .frame(width: 45, height: 45, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var amountWithChevron: some View {
        HStack(spacing: AppSpacing.small) {
            amount
            AppIcon("nav-arrow-right", size: 16)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var amount: some View {
        TransactionAmountText(
            amount: transaction.formattedAmount(),
            font: .body.weight(.medium),
            color: transaction.kind == .income ? AppColor.positive : .primary
        )
            .fixedSize(horizontal: false, vertical: true)
    }

    private var surface: some View {
        RoundedRectangle(cornerRadius: AppRadius.extraLarge)
            .fill(AppColor.elevatedSurface)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.extraLarge)
                    .strokeBorder(AppColor.separator.opacity(0.15), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(layers > 0 ? 0.06 : 0), radius: 3, y: 2)
    }
}
