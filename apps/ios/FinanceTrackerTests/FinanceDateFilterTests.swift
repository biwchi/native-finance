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
        func firstScrollView(in view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView { return scrollView }
            return view.subviews.lazy.compactMap { firstScrollView(in: $0) }.first
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let scenarios: [(FinanceDateFilter.Preset, CGFloat, DynamicTypeSize)] = [
            (.month, 390, .large), (.custom, 390, .large), (.allTime, 390, .large),
            (.last7Days, 390, .large), (.month, 320, .large), (.custom, 320, .large),
            (.month, 390, .accessibility3), (.custom, 390, .accessibility3)
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (preset, width, textSize) in scenarios {
                let filter = FinanceDateFilter(preset: preset, anchor: now, customEnd: now)
                let controller = UIHostingController(rootView:
                    AppColor.groupedBackground
                        .sheet(isPresented: .constant(true)) {
                            FinanceDateFilterSheet(selection: filter, calendar: self.calendar) { _, _ in }
                                .environment(\.calendar, self.calendar)
                                .environment(\.locale, self.locale)
                                .environment(\.dynamicTypeSize, textSize)
                        }
                        .preferredColorScheme(scheme))
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                try await Task.sleep(for: .milliseconds(650))
                controller.view.layoutIfNeeded()
                if !textSize.isAccessibilitySize {
                    let sheet = try XCTUnwrap(controller.presentedViewController)
                    let scrollView = try XCTUnwrap(firstScrollView(in: sheet.view))
                    XCTAssertLessThanOrEqual(scrollView.contentSize.height, scrollView.bounds.height + 1,
                                             "\(preset.rawValue) must show Apply without scrolling at width \(width)")
                }
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Date-filter-\(preset.rawValue)-\(Int(width))-\(textSize)-\(scheme)"
                attachment.lifetime = .keepAlways
                add(attachment)
                controller.dismiss(animated: false)
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }

    func testQuickFiltersReturnToCurrentPeriodAfterNavigating() {
        var draft = FinanceDateFilterSheet.Draft(selection: FinanceDateFilter(anchor: now), calendar: calendar)
        draft.shift(by: -1, now: now, calendar: calendar)
        XCTAssertEqual(draft.selection.anchor, date("2026-08-01T00:00:00Z"))
        for preset in FinanceDateFilter.Preset.allCases where preset != .custom {
            draft.select(preset, now: now, calendar: calendar)
            XCTAssertEqual(draft.selection.preset, preset)
            XCTAssertEqual(draft.selection.anchor, now)
        }
    }

    func testCustomDraftStartsWithTheDisplayedMonthAndClampsInvalidEndDates() {
        var draft = FinanceDateFilterSheet.Draft(selection: FinanceDateFilter(anchor: now), calendar: calendar)
        draft.shift(by: -1, now: now, calendar: calendar)
        draft.select(.custom, now: now, calendar: calendar)
        XCTAssertEqual(draft.selection.anchor, date("2026-08-01T00:00:00Z"))
        XCTAssertEqual(draft.selection.customEnd, date("2026-08-31T00:00:00Z"))

        draft.setStart(date("2026-09-12T18:00:00Z"), calendar: calendar)
        XCTAssertEqual(draft.selection.anchor, date("2026-09-12T00:00:00Z"))
        XCTAssertEqual(draft.selection.customEnd, draft.selection.anchor)
        draft.setEnd(date("2026-09-10T18:00:00Z"), calendar: calendar)
        XCTAssertEqual(draft.selection.customEnd, draft.selection.anchor)
    }

    func testCustomDraftSurvivesPresetChangesAndReopening() {
        var draft = FinanceDateFilterSheet.Draft(selection: FinanceDateFilter(anchor: now), calendar: calendar)
        draft.select(.custom, now: now, calendar: calendar)
        draft.setStart(date("2026-08-20T18:00:00Z"), calendar: calendar)
        draft.setEnd(date("2026-09-05T10:00:00Z"), calendar: calendar)
        let custom = draft.selection
        draft.select(.week, now: now, calendar: calendar)
        draft.select(.custom, now: now, calendar: calendar)
        XCTAssertEqual(draft.selection, custom)
        draft.select(.month, now: now, calendar: calendar)

        var reopened = FinanceDateFilterSheet.Draft(selection: draft.selection, savedCustom: draft.savedCustom, calendar: calendar)
        reopened.select(.custom, now: now, calendar: calendar)
        XCTAssertEqual(reopened.selection, custom)
    }

    func testRollingNavigationKeepsQuickModeAndRestoresTheLiveWindow() {
        var draft = FinanceDateFilterSheet.Draft(selection: FinanceDateFilter(preset: .last7Days, anchor: now), calendar: calendar)
        draft.shift(by: -1, now: now, calendar: calendar)
        XCTAssertEqual(draft.selection.preset, .last7Days)
        XCTAssertEqual(draft.selection.interval(now: now, calendar: calendar)?.start, date("2026-09-02T00:00:00Z"))
        XCTAssertEqual(draft.selection.interval(now: now, calendar: calendar)?.end, date("2026-09-09T00:00:00Z"))
        XCTAssertNil(draft.savedCustom)
        XCTAssertNotEqual(draft.selection.label(now: now, calendar: calendar, locale: locale), "Last 7 Days")

        var reopened = FinanceDateFilterSheet.Draft(selection: draft.selection, calendar: calendar)
        XCTAssertEqual(reopened.selection.preset, .last7Days)
        reopened.shift(by: 1, now: now, calendar: calendar)
        XCTAssertNil(reopened.selection.rollingAnchor)
        XCTAssertEqual(reopened.selection.label(now: now, calendar: calendar, locale: locale), "Last 7 Days")

        draft.select(.allTime, now: now, calendar: calendar)
        let allTime = draft.selection
        draft.shift(by: 1, now: now, calendar: calendar)
        XCTAssertEqual(draft.selection, allTime)
    }

    func testNavigatingEveryQuickPresetKeepsDateFieldsInCustomOnly() {
        for preset in FinanceDateFilter.Preset.allCases where preset != .custom && preset != .allTime {
            var draft = FinanceDateFilterSheet.Draft(selection: FinanceDateFilter(preset: preset, anchor: now), calendar: calendar)
            let current = draft.selection.interval(now: now, calendar: calendar)
            draft.shift(by: -1, now: now, calendar: calendar)
            XCTAssertEqual(draft.selection.preset, preset)
            XCTAssertEqual(draft.selection.interval(now: now, calendar: calendar)?.end, current?.start)
            draft.shift(by: 1, now: now, calendar: calendar)
            XCTAssertEqual(draft.selection.interval(now: now, calendar: calendar), current)
            XCTAssertNil(draft.savedCustom)
        }
    }

    @MainActor
    func testCompactDateLabelsRenderAtNarrowWidthAndAccessibilitySizes() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let content = VStack(spacing: 16) {
                    FinanceDatePickerButton(selection: .constant(FinanceDateFilter(anchor: now)))
                    FinanceDatePickerButton(selection: .constant(FinanceDateFilter(preset: .allTime)))
                        .disabled(true)
                    FinanceDatePickerButton(selection: .constant(FinanceDateFilter(preset: .custom,
                        anchor: date("2025-12-29T00:00:00Z"), customEnd: date("2026-09-15T00:00:00Z"))))
                }
                .padding(16)
                .environment(\.calendar, calendar)
                .environment(\.locale, locale)
                .environment(\.dynamicTypeSize, size)
                .background(AppColor.groupedBackground)
                .preferredColorScheme(scheme)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(windowScene: scene)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                let measured = controller.sizeThatFits(in: CGSize(width: 320, height: 1200))
                XCTAssertLessThanOrEqual(measured.width, 320)
                window.frame = CGRect(origin: .zero, size: measured)
                controller.view.frame = window.bounds
                try await Task.sleep(for: .milliseconds(200))
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Compact-date-\(scheme)-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
                window.rootViewController = nil
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
