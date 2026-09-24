import SwiftUI

struct GoalCard: View {
    let goal: SavingsGoal
    let currency: String
    let progress: GoalProgress?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.medium) {
                CategoryIcon(iconName: goal.icon, color: goal.color.swiftUIColor, size: 44)
                    .dynamicTypeSize(.large)
                Text(goal.name).font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if progress?.isComplete == true { GoalCompletionMark() }
            }
            if let progress {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                        amountSummary(progress)
                        percentage(progress)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                        amountSummary(progress).frame(maxWidth: .infinity, alignment: .leading)
                        percentage(progress)
                    }
                }
                VStack(spacing: AppSpacing.extraSmall) {
                    BudgetProgressBar(budgetProgress: progress.fraction, monthProgress: nil,
                                      tint: AppColor.iconForeground(for: goal.color.swiftUIColor))
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text("\(amount(progress.balance)) saved")
                            Spacer(minLength: AppSpacing.small)
                            Text("of \(amount(progress.target))")
                        }
                        VStack(alignment: .leading) {
                            Text("\(amount(progress.balance)) saved")
                            Text("of \(amount(progress.target))")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Text("Balance unavailable").font(.subheadline).foregroundStyle(.secondary)
                Text("Target \(amount(goal.target))").font(.caption).foregroundStyle(.secondary)
            }
            if let deadline = goal.deadline, let date = GoalDeadline.date(from: deadline) {
                HStack(spacing: AppSpacing.small) {
                    AppIcon("calendar", size: 14)
                    Text(date, format: .dateTime.month(.abbreviated).day().year())
                }
                .font(.caption)
                .foregroundStyle(deadline < GoalDeadline.string(from: .now) && progress?.isComplete != true
                                 ? AppColor.destructiveText : .secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(AppSpacing.large)
        .background(AppColor.elevatedSurface, in: RoundedRectangle(cornerRadius: AppRadius.groupedSection))
        .accessibilityElement(children: .combine)
    }

    private func amountSummary(_ progress: GoalProgress) -> Text {
        Text(amount(progress.isComplete ? progress.balance : progress.remaining))
            .font(.title2.weight(.semibold))
        + Text(progress.isComplete ? " saved" : " to go")
            .font(.subheadline).foregroundColor(.secondary)
    }

    private func percentage(_ progress: GoalProgress) -> some View {
        Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
            .font(.caption).foregroundStyle(.secondary).fixedSize()
    }

    private func amount(_ value: Decimal) -> String {
        MoneyFormatter.format(value, currency: currency, roundToWhole: roundTotals)
    }
}
