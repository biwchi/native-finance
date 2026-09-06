import XCTest
import SwiftUI
@testable import FinanceTracker

final class FinanceDateFilterTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
    private var now: Date { date("2026-09-15T12:00:00Z") }
    private let locale = Locale(identifier: "en_GB")

    func testFirstWeekdayPreferenceChangesWeeklyBoundariesAndKeepsTimeZone() throws {
        let anchor = date("2026-09-15T12:00:00Z")
        let monday = AppPreferences.calendar(firstWeekday: 2, base: calendar)
        let sunday = AppPreferences.calendar(firstWeekday: 1, base: calendar)
        let filter = FinanceDateFilter(preset: .week, anchor: anchor)
        XCTAssertEqual(filter.interval(calendar: monday)?.start, date("2026-09-14T00:00:00Z"))
        XCTAssertEqual(filter.interval(calendar: sunday)?.start, date("2026-09-13T00:00:00Z"))
        XCTAssertFalse(filter.contains(date("2026-09-13T12:00:00Z"), now: now, calendar: monday))
        XCTAssertTrue(filter.contains(date("2026-09-13T12:00:00Z"), now: now, calendar: sunday))
        for day in 1...7 {
            let selected = AppPreferences.calendar(firstWeekday: day, base: calendar)
            let start = try XCTUnwrap(filter.interval(calendar: selected)?.start)
            XCTAssertEqual(selected.component(.weekday, from: start), day)
            XCTAssertEqual(selected.timeZone, calendar.timeZone)
        }
        XCTAssertEqual(AppPreferences.calendar(firstWeekday: 0, base: calendar), calendar)
        XCTAssertEqual(AppPreferences.calendar(firstWeekday: 8, base: calendar), calendar)
    }

    func testReadableLabelsOnlyIncludeYearWhenNeeded() {
        XCTAssertEqual(label(.day, "2026-09-15T00:00:00Z"), "Today")
        XCTAssertEqual(label(.day, "2026-09-14T00:00:00Z"), "Yesterday")
        XCTAssertEqual(label(.day, "2026-09-03T00:00:00Z"), "3 September")
        XCTAssertEqual(label(.day, "2024-09-03T00:00:00Z"), "3 September 2024")
        XCTAssertEqual(label(.month, "2026-04-01T00:00:00Z"), "April")
        XCTAssertEqual(label(.month, "2024-04-01T00:00:00Z"), "April 2024")
        XCTAssertEqual(label(.year, "2024-04-01T00:00:00Z"), "2024")
        XCTAssertEqual(label(.last7Days, "2024-04-01T00:00:00Z"), "Last 7 Days")
        XCTAssertEqual(label(.last30Days, "2024-04-01T00:00:00Z"), "Last 30 Days")
        XCTAssertEqual(label(.allTime, "2024-04-01T00:00:00Z"), "All Time")
    }

    func testCustomLabelsCollapseSameDayAndRetainYearsAcrossNewYear() {
        let day = FinanceDateFilter(preset: .custom, anchor: now, customEnd: now)
        XCTAssertEqual(day.label(now: now, calendar: calendar, locale: locale), "Today")
        let range = FinanceDateFilter(preset: .custom, anchor: date("2025-12-29T00:00:00Z"), customEnd: date("2026-01-03T00:00:00Z"))
        let title = range.label(now: now, calendar: calendar, locale: locale)
        XCTAssertTrue(title.contains("2025"))
        XCTAssertTrue(title.contains("2026"))
        let current = FinanceDateFilter(preset: .custom, anchor: date("2026-09-03T00:00:00Z"), customEnd: date("2026-09-24T00:00:00Z"))
        let currentTitle = current.label(now: now, calendar: calendar, locale: locale)
        XCTAssertFalse(currentTitle.contains("2026"))
        XCTAssertTrue(currentTitle.contains("3"))
        XCTAssertTrue(currentTitle.contains("24"))
    }

    func testEveryPresetUsesCalendarBoundariesAndRollingDaysIncludeToday() throws {
        let expected: [(FinanceDateFilter.Preset, String, String)] = [
            (.day, "2026-09-15T00:00:00Z", "2026-09-16T00:00:00Z"),
            (.week, "2026-09-14T00:00:00Z", "2026-09-21T00:00:00Z"),
            (.biweekly, "2026-09-14T00:00:00Z", "2026-09-28T00:00:00Z"),
            (.month, "2026-09-01T00:00:00Z", "2026-10-01T00:00:00Z"),
            (.year, "2026-01-01T00:00:00Z", "2027-01-01T00:00:00Z"),
            (.last7Days, "2026-09-09T00:00:00Z", "2026-09-16T00:00:00Z"),
            (.last30Days, "2026-08-17T00:00:00Z", "2026-09-16T00:00:00Z")
        ]
        for (preset, start, end) in expected {
            let interval = try XCTUnwrap(FinanceDateFilter(preset: preset, anchor: now).interval(now: now, calendar: calendar))
            XCTAssertEqual(interval.start, date(start), preset.rawValue)
            XCTAssertEqual(interval.end, date(end), preset.rawValue)
        }
        XCTAssertNil(FinanceDateFilter(preset: .allTime).interval())
    }

    func testCustomRangeIncludesEntireLastDayAndNormalizesReversedDates() {
        let start = date("2026-09-03T16:00:00Z")
        let end = date("2026-09-24T08:00:00Z")
        for filter in [FinanceDateFilter(preset: .custom, anchor: start, customEnd: end),
                       FinanceDateFilter(preset: .custom, anchor: end, customEnd: start)] {
            XCTAssertTrue(filter.contains(date("2026-09-03T00:00:00Z"), now: now, calendar: calendar))
            XCTAssertTrue(filter.contains(date("2026-09-24T23:59:59Z"), now: now, calendar: calendar))
            XCTAssertFalse(filter.contains(date("2026-09-02T23:59:59Z"), now: now, calendar: calendar))
            XCTAssertFalse(filter.contains(date("2026-09-25T00:00:00Z"), now: now, calendar: calendar))
        }
    }

    func testNavigationHandlesLeapYearMonthEndsAndYearRollover() throws {
        let january = FinanceDateFilter(preset: .month, anchor: date("2024-01-31T12:00:00Z"))
        let february = january.shifted(by: 1, calendar: calendar)
        XCTAssertEqual(february.anchor, date("2024-02-01T00:00:00Z"))
        XCTAssertEqual(february.shifted(by: 1, calendar: calendar).anchor, date("2024-03-01T00:00:00Z"))
        XCTAssertEqual(january.shifted(by: -1, calendar: calendar).anchor, date("2023-12-01T00:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(february.interval(calendar: calendar)).duration, 29 * 86400)
        let fortnight = FinanceDateFilter(preset: .biweekly, anchor: now)
        XCTAssertEqual(fortnight.shifted(by: -1, calendar: calendar).anchor, date("2026-08-31T00:00:00Z"))
    }

    func testCustomAndRollingPeriodsCanMoveInBothDirections() {
        for preset in [FinanceDateFilter.Preset.last7Days, .last30Days, .custom] {
            let filter = FinanceDateFilter(preset: preset, anchor: date("2026-09-03T00:00:00Z"), customEnd: now)
            let original = filter.interval(now: now, calendar: calendar)
            let previous = filter.shifted(by: -1, now: now, calendar: calendar)
            XCTAssertEqual(previous.interval(calendar: calendar)?.end, original?.start)
            XCTAssertEqual(previous.shifted(by: 1, calendar: calendar).interval(calendar: calendar), original)
        }
        let allTime = FinanceDateFilter(preset: .allTime)
        XCTAssertEqual(allTime.shifted(by: -1), allTime)
    }

    func testDayAndRollingWindowRespectDaylightSavingTime() throws {
        var local = calendar
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let spring = date("2026-03-08T19:00:00Z")
        let day = try XCTUnwrap(FinanceDateFilter(preset: .day, anchor: spring).interval(calendar: local))
        XCTAssertEqual(day.duration, 23 * 3600)
        let week = try XCTUnwrap(FinanceDateFilter(preset: .last7Days).interval(now: spring, calendar: local))
        XCTAssertEqual(week.start, date("2026-03-02T08:00:00Z"))
        XCTAssertEqual(week.end, date("2026-03-09T07:00:00Z"))
    }

    func testLedgerAndTotalsAgreeForEveryPresetWithoutCountingDebtsAsSpending() {
        let rows = [transaction(.expense, 10, "2026-09-03T00:00:00Z"),
                    transaction(.expense, 20, "2026-09-15T23:59:59Z"),
                    transaction(.expense, 30, "2026-09-16T00:00:00Z"),
                    transaction(.income, 100, "2026-09-15T12:00:00Z"),
                    transaction(.debt, 600, "2026-09-15T12:00:00Z")]
        for preset in FinanceDateFilter.Preset.allCases {
            let filter = FinanceDateFilter(preset: preset, anchor: now, customEnd: now)
            let visible = FinanceOverviewData.transactions(rows, in: filter, now: now, calendar: calendar)
            let summary = DashboardInsights.calculate(transactions: rows, filter: filter, now: now, calendar: calendar)
            let expectedSpent = visible.filter { $0.kind == .expense }.reduce(Decimal.zero) { $0 + Decimal(string: $1.amount)! }
            XCTAssertEqual(summary.spent, expectedSpent, preset.rawValue)
            XCTAssertEqual(summary.income, 100, preset.rawValue)
            XCTAssertEqual(summary.net, 100 - expectedSpent, preset.rawValue)
        }
        XCTAssertEqual(DashboardInsights.calculate(transactions: rows, filter: FinanceDateFilter(anchor: now), now: now, calendar: calendar).spent, 30)
        XCTAssertEqual(DashboardInsights.calculate(transactions: rows, filter: FinanceDateFilter(preset: .allTime), now: now, calendar: calendar).spent, 60)
    }

    func testPreviousPeriodsUseMatchingElapsedDaysAndFullCompletedMonths() throws {
        let expected: [(FinanceDateFilter.Preset, String, String)] = [
            (.day, "2026-09-14T00:00:00Z", "2026-09-15T00:00:00Z"),
            (.week, "2026-09-07T00:00:00Z", "2026-09-09T00:00:00Z"),
            (.biweekly, "2026-08-31T00:00:00Z", "2026-09-02T00:00:00Z"),
            (.month, "2026-08-01T00:00:00Z", "2026-08-16T00:00:00Z"),
            (.last7Days, "2026-09-02T00:00:00Z", "2026-09-09T00:00:00Z"),
            (.last30Days, "2026-07-18T00:00:00Z", "2026-08-17T00:00:00Z")
        ]
        for (preset, start, end) in expected {
            let previous = try XCTUnwrap(FinanceDateFilter(preset: preset, anchor: now)
                .comparisonInterval(now: now, calendar: calendar))
            XCTAssertEqual(previous.start, date(start), preset.rawValue)
            XCTAssertEqual(previous.end, date(end), preset.rawValue)
        }
        let february = FinanceDateFilter(anchor: date("2026-02-15T00:00:00Z"))
        XCTAssertEqual(february.comparisonInterval(now: now, calendar: calendar),
                       DateInterval(start: date("2026-01-01T00:00:00Z"), end: date("2026-02-01T00:00:00Z")))
        XCTAssertNil(FinanceDateFilter(preset: .allTime).comparisonInterval(now: now, calendar: calendar))
    }

    func testCustomComparisonAndSpendingTrendUseExclusiveBoundaries() throws {
        let filter = FinanceDateFilter(preset: .custom, anchor: date("2026-09-12T00:00:00Z"),
                                       customEnd: date("2026-09-10T00:00:00Z"))
        let previous = try XCTUnwrap(filter.comparisonInterval(now: now, calendar: calendar))
        XCTAssertEqual(previous.start, date("2026-09-07T00:00:00Z"))
        XCTAssertEqual(previous.end, date("2026-09-10T00:00:00Z"))
        let rows = [transaction(.expense, 900, "2026-09-06T23:59:59Z"),
                    transaction(.expense, 100, "2026-09-07T00:00:00Z"),
                    transaction(.expense, 100, "2026-09-09T23:59:59Z"),
                    transaction(.income, 1000, "2026-09-08T00:00:00Z"),
                    transaction(.debt, 600, "2026-09-08T00:00:00Z"),
                    transaction(.expense, 184, "2026-09-10T00:00:00Z"),
                    transaction(.expense, 900, "2026-09-13T00:00:00Z")]
        let summary = DashboardInsights.calculate(transactions: rows, filter: filter, now: now, calendar: calendar)
        XCTAssertEqual(summary.previousSpent, 200)
        XCTAssertEqual(summary.spent, 184)
        XCTAssertEqual(summary.comparisonPercent, -8)
        let empty = DashboardInsights.calculate(transactions: [], filter: filter, now: now, calendar: calendar)
        XCTAssertEqual(empty.income, 0)
        XCTAssertEqual(empty.spent, 0)
        XCTAssertEqual(empty.net, 0)
        XCTAssertNil(empty.comparisonPercent)
    }

    func testSpendingComparisonUsesPreviousRangeForEveryBoundedPreset() throws {
        for preset in FinanceDateFilter.Preset.allCases where preset != .allTime {
            let filter = FinanceDateFilter(preset: preset, anchor: now, customEnd: now)
            let selected = try XCTUnwrap(filter.transactionInterval(now: now, calendar: calendar))
            let previous = try XCTUnwrap(filter.comparisonInterval(now: now, calendar: calendar))
            let formatter = ISO8601DateFormatter()
            let rows = [transaction(.expense, 100, formatter.string(from: previous.start)),
                        transaction(.income, 500, formatter.string(from: previous.start)),
                        transaction(.debt, 900, formatter.string(from: previous.start)),
                        transaction(.expense, 92, formatter.string(from: selected.start))]
            let insights = DashboardInsights.calculate(transactions: rows, filter: filter, now: now,
                                                      calendar: calendar, monthlyLimit: 2400)
            XCTAssertEqual(insights.spent, 92, preset.rawValue)
            XCTAssertEqual(insights.previousSpent, 100, preset.rawValue)
            XCTAssertEqual(insights.comparisonPercent, -8, preset.rawValue)
            XCTAssertEqual(insights.hasBudget, preset == .month)
        }
    }

    func testComparisonDaysRemainAlignedAcrossDaylightSavingTime() throws {
        var local = calendar
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let filter = FinanceDateFilter(preset: .custom, anchor: date("2026-03-09T07:00:00Z"),
                                       customEnd: date("2026-03-11T07:00:00Z"))
        let previous = try XCTUnwrap(filter.comparisonInterval(now: now, calendar: local))
        XCTAssertEqual(previous.start, date("2026-03-06T08:00:00Z"))
        XCTAssertEqual(previous.end, date("2026-03-09T07:00:00Z"))
        XCTAssertEqual(previous.duration, 71 * 3600)
    }

    @MainActor
    func testDateFilterSheetsRenderInLightAndDark() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            for isCustom in [true, false] {
                let controller = UIHostingController(rootView:
                    FinanceDateFilterSheet(selection: FinanceDateFilter(anchor: now), isCustom: isCustom, calendar: calendar) { _ in }
                        .environment(\.calendar, calendar)
                        .environment(\.locale, locale)
                        .preferredColorScheme(scheme))
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 390, height: isCustom ? 440 : 750)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                try await Task.sleep(for: .milliseconds(200))
                controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Date-filter-\(isCustom ? "custom" : "date")-\(scheme)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }

    private func label(_ preset: FinanceDateFilter.Preset, _ anchor: String) -> String {
        FinanceDateFilter(preset: preset, anchor: date(anchor)).label(now: now, calendar: calendar, locale: locale)
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func transaction(_ kind: TransactionKind, _ amount: Int, _ at: String) -> FinanceTransaction {
        FinanceTransaction(id: UUID(), accountId: UUID(), kind: kind, amount: String(amount), currency: "USD",
                           category: nil, merchant: nil, note: nil, occurredAt: date(at), createdAt: date(at), updatedAt: date(at))
    }
}
