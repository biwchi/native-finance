import SwiftUI

struct MonthlySummaryCompactView: View {
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    let state: MonthlySummaryState
    var showsPlannedBills = false
    var plannedBills: PlannedBillsSummary? = nil
    var isLoadingPlannedBills = false
    var surface: FinanceCardSurface = .standard

    var body: some View {
        MonthlySummaryCard(monthTitle: state.monthTitle, surface: surface) {
            Text(state.status.displayText)
                .foregroundStyle(state.status == .onTrack ? .secondary : statusTint)
        } content: {
            MonthlySummaryContent {
                MonthlySummaryAmount(amount: displayState.amountText, suffix: state.amountSuffix)
                    .foregroundStyle(state.status == .overLimit ? statusTint : .primary)
            } caption: {
                MonthlySummaryRow {
                    Text(displayState.spendingText)
                } trailing: {
                    Text(state.timeRemainingText)
                }
            }

            BudgetProgressBar(
                budgetProgress: state.budgetProgress,
                monthProgress: state.isCurrentMonth ? state.monthProgress : nil,
                tint: state.status == .onTrack ? AppColor.accent : statusTint
            )

            if showsPlannedBills {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let plannedBills {
                        MonthlySummaryRow {
                            Text("After planned bills")
                                .foregroundStyle(.secondary)
                        } trailing: {
                            Text(MoneyFormatter.format(plannedBills.afterBills, currency: state.currency, roundToWhole: roundTotals))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        if let daily = plannedBills.dailyAmount, let range = plannedBills.dailyRange {
                            Text("\(MoneyFormatter.format(daily, currency: state.currency, roundToWhole: roundTotals))/day · \(dateRange(range))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } else if isLoadingPlannedBills {
                        ProgressView("Loading planned bills")
                            .font(.footnote)
                    } else {
                        Text("Planned bills unavailable")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, AppSpacing.compact)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var displayState: MonthlySummaryState {
        var value = state
        value.roundTotals = roundTotals
        return value
    }

    private var statusTint: Color { state.status.tint }

    private func dateRange(_ range: ClosedRange<Date>) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = state.locale
        formatter.calendar = state.calendar
        formatter.timeZone = state.calendar.timeZone
        formatter.dateTemplate = "d MMM"
        return formatter.string(from: range.lowerBound, to: range.upperBound)
    }

    private var accessibilityLabel: String {
        guard showsPlannedBills else { return displayState.accessibilityLabel }
        guard let plannedBills else {
            return displayState.accessibilityLabel + ". " + (isLoadingPlannedBills ? "Loading planned bills" : "Planned bills unavailable")
        }
        let remaining = MoneyFormatter.spoken(plannedBills.afterBills, currency: state.currency, locale: state.locale, roundToWhole: roundTotals)
        var label = displayState.accessibilityLabel + ". After planned bills, " + remaining
        if let daily = plannedBills.dailyAmount, let range = plannedBills.dailyRange {
            label += ". " + MoneyFormatter.spoken(daily, currency: state.currency, locale: state.locale, roundToWhole: roundTotals)
                + " per day, " + dateRange(range)
        }
        return label
    }
}
