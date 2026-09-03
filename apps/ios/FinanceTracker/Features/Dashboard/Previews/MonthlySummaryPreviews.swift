import SwiftUI

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
    .background(AppColor.groupedBackground)
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
    .background(AppColor.groupedBackground)
    .preferredColorScheme(.light)
}
#endif
