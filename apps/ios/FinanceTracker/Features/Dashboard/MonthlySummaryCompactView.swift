import SwiftUI

struct MonthlySummaryCompactView: View {
    let state: MonthlySummaryState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .title) private var amountSize = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    month.fixedSize()
                    Spacer(minLength: 12)
                    status.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    month
                    status
                }
            }
            .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                (
                    Text(state.amountText)
                        .font(.system(size: amountSize, weight: .semibold))
                    + Text(" " + state.amountSuffix)
                        .font(.title3.weight(.regular))
                )
                .foregroundStyle(state.status == .overLimit ? statusTint : .primary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        spending.fixedSize()
                        Spacer(minLength: 12)
                        timeRemaining.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        spending
                        timeRemaining
                    }
                }
                .font(.footnote)
                .foregroundStyle(contrast == .increased ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            BudgetProgressBar(
                budgetProgress: state.budgetProgress,
                monthProgress: state.isCurrentMonth ? state.monthProgress : nil,
                tint: state.status == .onTrack ? .accentColor : statusTint
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 16 : 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
    }

    private var month: some View {
        Text(state.monthTitle)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var status: some View {
        Text(state.status.displayText)
            .foregroundStyle(state.status == .onTrack ? .secondary : statusTint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var spending: some View {
        Text(state.spendingText).monospacedDigit()
    }

    private var timeRemaining: some View {
        Text(state.timeRemainingText).monospacedDigit()
    }

    private var statusTint: Color { state.status.tint(for: colorScheme) }
}

extension BudgetStatus {
    func tint(for scheme: ColorScheme) -> Color {
        switch self {
        case .onTrack: .accentColor
        case .watchSpending, .nearLimit:
            scheme == .dark
                ? Color(red: 1, green: 0.72, blue: 0.32)
                : Color(red: 0.48, green: 0.28, blue: 0.02)
        case .overLimit:
            scheme == .dark
                ? Color(red: 1, green: 0.48, blue: 0.44)
                : Color(red: 0.65, green: 0.12, blue: 0.10)
        }
    }
}

struct MonthlySummaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: configuration.isPressed)
    }
}

#if DEBUG
enum MonthlySummaryPreviewData {
    struct Sample: Identifiable {
        let name: String
        let state: MonthlySummaryState
        var width: CGFloat = 353
        var dynamicTypeSize: DynamicTypeSize = .large
        var id: String { name }
    }

    static let samples: [Sample] = [
        sample("On track", spent: 760),
        sample("Watch spending", spent: 1_400, day: 7),
        sample("Near limit", spent: 1_850),
        sample("Over budget", budget: Decimal(string: "21.79")!, spent: Decimal(string: "37.29")!),
        sample("Zero spending", spent: 0),
        sample("Large amounts", budget: 2_000_000_000, spent: Decimal(string: "760000000.45")!),
        sample("KZT", budget: 1_200_000, spent: Decimal(string: "425265.84")!,
               currency: "KZT", locale: "kk_KZ"),
        sample("Accessibility", spent: 760, dynamicTypeSize: .accessibility3),
        sample("320 pt screen", budget: Decimal(string: "21.79")!,
               spent: Decimal(string: "37.29")!, width: 288),
    ]

    private static func sample(
        _ name: String, budget: Decimal = 2_000, spent: Decimal, day: Int = 14,
        currency: String = "USD", locale: String = "en_US", width: CGFloat = 353,
        dynamicTypeSize: DynamicTypeSize = .large
    ) -> Sample {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!
        let interval = calendar.dateInterval(of: .month, for: date)!
        return Sample(name: name, state: MonthlySummaryState(
            monthlyBudget: budget, amountSpent: spent, currentDate: date,
            startOfMonth: interval.start, endOfMonth: interval.end,
            currency: currency, locale: Locale(identifier: locale), calendar: calendar
        )!, width: width, dynamicTypeSize: dynamicTypeSize)
    }
}

#Preview("Monthly summary · dark states") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(MonthlySummaryPreviewData.samples) { sample in
                MonthlySummaryCompactView(state: sample.state)
                    .frame(width: sample.width)
                    .environment(\.dynamicTypeSize, sample.dynamicTypeSize)
            }
        }
        .padding(16)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .preferredColorScheme(.dark)
}

#Preview("Monthly summary · light states") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(MonthlySummaryPreviewData.samples) { sample in
                MonthlySummaryCompactView(state: sample.state)
                    .frame(width: sample.width)
                    .environment(\.dynamicTypeSize, sample.dynamicTypeSize)
            }
        }
        .padding(16)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .preferredColorScheme(.light)
}
#endif
