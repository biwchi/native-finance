import SwiftUI
import UIKit
import XCTest
@testable import FinanceTracker

final class MonthlySummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testStatusPrecedenceAndPaceTolerance() throws {
        XCTAssertEqual(try state(spent: 760).status, .onTrack)
        XCTAssertEqual(try state(spent: 1_400, day: 7).status, .watchSpending)
        XCTAssertEqual(try state(spent: 1_850, day: 7).status, .nearLimit)
        XCTAssertEqual(try state(spent: 2_000).status, .nearLimit)
        XCTAssertEqual(try state(spent: 2_001).status, .overLimit)
        XCTAssertEqual(try state(spent: 0, day: 1).status, .onTrack)
        XCTAssertEqual(try state(spent: 1_000, day: 16).status, .onTrack)
        XCTAssertEqual(try state(spent: 1_000, day: 8).status, .watchSpending)
    }

    func testExactFractionalAmountsAndAccessibility() throws {
        let summary = try state(budget: Decimal(string: "21.79"), spent: Decimal(string: "37.29")!)
        XCTAssertEqual(summary.remaining, Decimal(string: "-15.50"))
        XCTAssertEqual(summary.amountText, "$15.50")
        XCTAssertEqual(summary.spendingText, "$37.29 of $21.79 spent")
        XCTAssertEqual(summary.amountSuffix, "over")
        XCTAssertGreaterThan(summary.budgetProgress, 1)
        XCTAssertTrue(summary.accessibilityLabel.contains("15.50 US dollars over budget"))
        XCTAssertTrue(summary.accessibilityLabel.contains("Over limit"))

        let healthy = try state(spent: 760)
        XCTAssertEqual(healthy.amountText, "$1,240")
        XCTAssertTrue(healthy.accessibilityLabel.contains("September budget"))
        XCTAssertTrue(healthy.accessibilityLabel.contains("1,240 US dollars remaining"))
        XCTAssertTrue(healthy.accessibilityLabel.contains("16 days left"))
    }

    func testMissingAndInvalidInputsHideSummary() throws {
        for budget: Decimal? in [nil, 0, -1, .nan] {
            XCTAssertNil(makeState(budget: budget, spent: 20))
        }
        XCTAssertNil(makeState(budget: 20, spent: .nan))
        let summary = try state(spent: -20)
        XCTAssertEqual(summary.amountSpent, 0)
        XCTAssertEqual(summary.remaining, 2_000)
        XCTAssertEqual(summary.budgetProgress, 0)
    }

    func testCalendarBoundariesLeapYearAndDST() throws {
        let leap = try state(spent: 0, year: 2024, month: 2, day: 1)
        XCTAssertEqual(leap.daysRemaining, 28)
        XCTAssertEqual(try state(spent: 0, year: 2025, month: 2, day: 1).daysRemaining, 27)
        let last = try state(spent: 0, year: 2024, month: 2, day: 29)
        XCTAssertEqual(last.daysRemaining, 0)
        XCTAssertEqual(last.timeRemainingText, "Last day")

        var dstCalendar = calendar
        dstCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let interval = try XCTUnwrap(dstCalendar.dateInterval(of: .month, for: now))
        let dst = try XCTUnwrap(MonthlySummaryState(
            monthlyBudget: 2_000, amountSpent: 0, currentDate: now,
            startOfMonth: interval.start, endOfMonth: interval.end,
            currency: "USD", locale: Locale(identifier: "en_US"), calendar: dstCalendar
        ))
        XCTAssertEqual(dst.daysRemaining, 23)
        XCTAssertEqual(dst.monthProgress, now.timeIntervalSince(interval.start) / interval.duration,
                       accuracy: 0.000001)

        for (date, progress, label) in [
            (interval.start.addingTimeInterval(-1), 0.0, "Upcoming month"),
            (interval.end, 1.0, "Month ended"),
        ] {
            let summary = try XCTUnwrap(MonthlySummaryState(
                monthlyBudget: 2_000, amountSpent: 0, currentDate: date,
                startOfMonth: interval.start, endOfMonth: interval.end,
                currency: "USD", locale: Locale(identifier: "en_US"), calendar: dstCalendar
            ))
            XCTAssertEqual(summary.monthProgress, progress)
            XCTAssertEqual(summary.timeRemainingText, label)
            XCTAssertFalse(summary.isCurrentMonth)
        }
    }

    func testLocaleAndCurrencyPrecision() throws {
        let yen = try state(budget: 2_000, spent: Decimal(string: "760.45")!, currency: "JPY", locale: "ja_JP")
        XCTAssertFalse(yen.amountText.contains("."))
        let dinar = try state(budget: 2_000, spent: Decimal(string: "760.125")!, currency: "KWD", locale: "en_US")
        XCTAssertTrue(dinar.amountText.contains("1,239.875"))
        let euro = try state(spent: 760, currency: "EUR", locale: "de_DE")
        XCTAssertTrue(euro.amountText.contains("1.240"))
        XCTAssertTrue(euro.amountText.contains("€"))
        let tenge = try state(spent: 760, currency: "KZT", locale: "kk_KZ")
        XCTAssertTrue(tenge.amountText.contains("₸"))
        XCTAssertFalse(tenge.monthTitle.contains("September"))
        let large = try state(budget: 2_000_000_000_000_000, spent: 760_000_000_000_000)
        XCTAssertEqual(large.remaining, 1_240_000_000_000_000)
        XCTAssertEqual(large.budgetProgress, 0.38, accuracy: 0.000001)
    }

    @MainActor
    func testRenderAllPreviewStates() throws {
        for scheme in [ColorScheme.dark, .light] {
            for sample in MonthlySummaryPreviewData.samples {
                let renderer = ImageRenderer(content: MonthlySummaryCompactView(state: sample.state)
                    .frame(width: sample.width)
                    .environment(\.dynamicTypeSize, sample.dynamicTypeSize)
                    .environment(\.colorScheme, scheme)
                )
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, sample.width)
                if sample.name == "On track" {
                    XCTAssertLessThanOrEqual(image.size.height, 125)
                    XCTAssertGreaterThanOrEqual(image.size.height, 105)
                }
                if sample.name == "Accessibility" {
                    XCTAssertGreaterThan(image.size.height, 200)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(sample.name)-\(scheme)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testDashboardLayoutAtSeveralWidths() async throws {
        let now = Date.now
        let account = Account(id: UUID(), name: "Everyday card", type: .checking, currency: "KZT",
                              icon: "credit-card", iconColor: .blue, createdAt: "", updatedAt: "")
        let budget = MonthlyBudget(id: UUID(), accountId: account.id, month: BudgetMonth.key(for: now),
                                   currency: "KZT", monthlyLimit: "10000", groups: [], categoryAssignments: [],
                                   createdAt: now, updatedAt: now)
        let transactions = [FinanceTransaction(
            id: UUID(), accountId: account.id, kind: .expense, amount: "17116", currency: "KZT",
            category: nil, note: "Groceries", occurredAt: now, createdAt: now, updatedAt: now
        ), FinanceTransaction(
            id: UUID(), accountId: account.id, kind: .income, amount: "1800000", currency: "KZT",
            category: nil, note: "Salary", occurredAt: now, createdAt: now, updatedAt: now
        )]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let configurations: [(CGFloat, ColorScheme, UIAccessibilityContrast)] = [
            (320, .dark, .normal), (393, .dark, .high),
            (440, .dark, .normal), (393, .light, .high),
        ]
        for (width, scheme, contrast) in configurations {
            let view = DashboardView()
                .environmentObject(AccountStore.preview(accounts: [account], selectedAccountID: account.id))
                .environmentObject(BudgetStore.preview(budget))
                .environmentObject(ExchangeRateStore())
                .environmentObject(TransactionStore.preview(transactions: transactions))
                .environment(\.locale, Locale(identifier: "en_US"))
                .preferredColorScheme(scheme)
            let controller = UIHostingController(rootView: view)
            controller.traitOverrides.accessibilityContrast = contrast
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(300))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Dashboard-\(Int(width))-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    private func state(
        budget: Decimal? = 2_000, spent: Decimal, year: Int = 2026, month: Int = 9,
        day: Int = 14, currency: String = "USD", locale: String = "en_US"
    ) throws -> MonthlySummaryState {
        try XCTUnwrap(makeState(budget: budget, spent: spent, year: year, month: month,
                               day: day, currency: currency, locale: locale))
    }

    private func makeState(
        budget: Decimal?, spent: Decimal, year: Int = 2026, month: Int = 9, day: Int = 14,
        currency: String = "USD", locale: String = "en_US"
    ) -> MonthlySummaryState? {
        let now = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        let interval = calendar.dateInterval(of: .month, for: now)!
        return MonthlySummaryState(
            monthlyBudget: budget, amountSpent: spent, currentDate: now,
            startOfMonth: interval.start, endOfMonth: interval.end,
            currency: currency, locale: Locale(identifier: locale), calendar: calendar
        )
    }
}
