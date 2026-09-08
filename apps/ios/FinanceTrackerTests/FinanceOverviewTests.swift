import XCTest
import SwiftUI
import UIKit
@testable import FinanceTracker

final class FinanceOverviewTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private let accountID = UUID()
    private var now: Date { date("2026-09-15T12:00:00Z") }

    func testRecurringRemindersIncludeEntireLastDayAndSortNearestFirst() {
        let today = bill(10, at: "2026-09-15T18:00:00Z")
        let tomorrow = bill(20, at: "2026-09-16T09:00:00Z", kind: .income)
        let lastDay = bill(30, at: "2026-09-18T23:59:59Z")
        let rows = [lastDay, bill(40, at: "2026-09-19T00:00:00Z"), tomorrow,
                    bill(50, at: "2026-09-15T11:59:59Z"), today]
        let reminders = FinanceOverviewData.upcomingReminders(
            rows, daysBefore: AppPreferences.defaultRecurringReminderDays, now: now, calendar: calendar
        )
        XCTAssertEqual(reminders.map(\.id), [today.id, tomorrow.id, lastDay.id])
        XCTAssertEqual(AppPreferences.defaultRecurringReminderDays, 3)
    }

    func testReminderWindowChangesAndEmptyResults() {
        let today = bill(10, at: "2026-09-15T18:00:00Z")
        let nextWeek = bill(20, at: "2026-09-22T09:00:00Z")
        XCTAssertEqual(FinanceOverviewData.upcomingReminders([nextWeek, today], daysBefore: 0,
            now: now, calendar: calendar).map(\.id), [today.id])
        XCTAssertEqual(FinanceOverviewData.upcomingReminders([nextWeek, today], daysBefore: 7,
            now: now, calendar: calendar).map(\.id), [today.id, nextWeek.id])
        XCTAssertTrue(FinanceOverviewData.upcomingReminders([nextWeek], daysBefore: 3,
            now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(FinanceOverviewData.upcomingReminders([], daysBefore: 3,
            now: now, calendar: calendar).isEmpty)
    }

    func testRemindersRespectEndDateAndStableOrderingForSameDueTime() {
        let first = bill(10, at: "2026-09-16T09:00:00Z")
        let second = bill(20, at: "2026-09-16T09:00:00Z")
        let ended = bill(30, at: "2026-09-16T09:00:00Z", end: "2026-09-16T08:00:00Z")
        let expected = [first, second].sorted { $0.id.uuidString < $1.id.uuidString }.map(\.id)
        XCTAssertEqual(FinanceOverviewData.upcomingReminders([second, ended, first], daysBefore: 3,
            now: now, calendar: calendar).map(\.id), expected)
    }

    func testReminderWindowUsesLocalCalendarDaysAcrossDaylightSaving() {
        var local = calendar
        local.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let reference = date("2026-03-07T20:00:00Z")
        let lastMinute = bill(10, at: "2026-03-09T06:59:59Z")
        let nextDay = bill(20, at: "2026-03-09T07:00:00Z")
        XCTAssertEqual(FinanceOverviewData.upcomingReminders([nextDay, lastMinute], daysBefore: 1,
            now: reference, calendar: local).map(\.id), [lastMinute.id])
    }

    @MainActor
    func testRecurringReminderLayouts() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let health = TransactionCategory(id: UUID(), systemKey: nil, name: "Health", kind: .expense,
            icon: "heart", color: .red, isSystem: false, examples: nil, sortOrder: nil,
            createdAt: nil, updatedAt: nil)
        for scheme in [ColorScheme.light, .dark] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                for count in [1, 2, 5] {
                    let transaction = UpcomingTransaction(id: UUID(), accountId: accountID, kind: .expense,
                        amount: "12.99", currency: "USD", category: count == 5 ? nil : health,
                        merchant: nil, payee: nil, note: count == 2 ? "Monthly checkup" : count == 5 ? "  \n " : nil,
                        frequency: .monthly, occurredAt: date("2026-09-16T09:00:00Z"))
                    let view = DashboardUpcomingReminder(transaction: transaction, count: count, now: now)
                        .padding(20)
                        .frame(width: 320)
                        .background(AppColor.groupedBackground)
                        .environment(\.calendar, calendar)
                        .environment(\.dynamicTypeSize, textSize)
                        .preferredColorScheme(scheme)
                        .fixedSize(horizontal: false, vertical: true)
                    .ignoresSafeArea()
                    let controller = UIHostingController(rootView: view)
                    controller.safeAreaRegions = []
                    let window = UIWindow(windowScene: scene)
                    window.rootViewController = controller
                    window.makeKeyAndVisible()
                    defer { window.isHidden = true }
                    let size = controller.sizeThatFits(in: CGSize(width: 320, height: 2000))
                    XCTAssertEqual(size.width, 320, accuracy: 1)
                    XCTAssertLessThan(size.height, textSize.isAccessibilitySize ? 700 : 230)
                    window.frame = CGRect(origin: .zero, size: size)
                    controller.view.frame = window.bounds
                    try await Task.sleep(for: .milliseconds(100))
                    controller.view.layoutIfNeeded()
                    let image = UIGraphicsImageRenderer(size: size).image { _ in
                        XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Reminder-\(count)-\(scheme)-\(textSize)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testMonthLedgerMatchesSummaryAndSearchDoesNotChangeTotals() {
        let rows = [transaction(100, at: "2026-09-01T00:00:00Z"),
                    transaction(200, at: "2026-09-15T18:00:00Z"),
                    transaction(900, at: "2026-09-16T00:00:00Z"),
                    transaction(700, at: "2026-08-31T23:59:59Z")]
        let visible = FinanceOverviewData.transactions(rows, in: now, now: now, calendar: calendar)
        let summary = DashboardInsights.calculate(transactions: rows, month: now, now: now,
                                                  calendar: calendar, monthlyLimit: nil)
        XCTAssertEqual(visible.map(\.amount), ["200", "100"])
        XCTAssertEqual(summary.spent, 300)
        XCTAssertTrue(FinanceOverviewData.matches(rows[0], query: "CAFE", accounts: []))
        XCTAssertTrue(FinanceOverviewData.matches(rows[0], query: "100", accounts: []))
        XCTAssertFalse(FinanceOverviewData.matches(rows[0], query: "rent", accounts: []))
    }

    func testDashboardBudgetHeaderRequiresUsableLimitRegardlessOfActivity() {
        for (spent, income) in [(0, 0), (100, 0), (0, 100), (100, 100)] {
            for limit: Decimal? in [nil, 0, -1, .nan, 2400] {
                let insights = DashboardInsights(income: Decimal(income), spent: Decimal(spent), previousSpent: 0,
                                                 net: Decimal(income - spent), monthlyLimit: limit)
                XCTAssertEqual(insights.hasBudget, limit == 2400)
                XCTAssertEqual(insights.net, Decimal(income - spent))
            }
        }
    }

    func testAfterBillsAndDailyAmountUseRealBudgetAndCalendarDays() throws {
        let bills = [bill(6000, at: "2026-09-16T09:00:00Z"), bill(300, at: "2026-09-18T09:00:00Z")]
        let result = try forecast(spent: 10033, bills: bills)
        XCTAssertEqual(result.planned, 6300)
        XCTAssertEqual(result.afterBills, 3667)
        XCTAssertEqual(result.dailyAmount, Decimal(string: "244.46"))
        XCTAssertEqual(result.dailyRange?.lowerBound, date("2026-09-16T00:00:00Z"))
        XCTAssertEqual(result.dailyRange?.upperBound, date("2026-09-30T00:00:00Z"))
    }

    func testRepeatsRespectEndDatesAndDoNotDoubleCountRecordedFuturePayments() throws {
        let daily = bill(50, at: "2026-09-16T09:00:00Z", frequency: .daily, end: "2026-09-18T09:00:00Z")
        let weekly = bill(200, at: "2026-09-16T09:00:00Z", frequency: .weekly)
        var recorded = transaction(50, at: "2026-09-16T09:00:00Z")
        recorded.recurrence = daily.recurrence
        let rows = [recorded, transaction(300, at: "2026-09-20T09:00:00Z")]
        let result = try forecast(spent: 0, bills: [daily, weekly], transactions: rows)
        XCTAssertEqual(result.planned, 1050) // 3 daily + 3 weekly + one future entry.
    }

    func testBillAlreadyIncludedInCurrentDaySpendingIsNotSubtractedAgain() throws {
        let dueToday = bill(100, at: "2026-09-15T18:00:00Z")
        var recorded = transaction(100, at: "2026-09-15T18:00:00Z")
        recorded.recurrence = dueToday.recurrence
        let result = try forecast(spent: 100, bills: [dueToday], transactions: [recorded])
        XCTAssertEqual(result.planned, 0)
        XCTAssertEqual(result.afterBills, 19900)
    }

    func testMonthlyForecastPreservesOriginalMonthEndAnchor() throws {
        let monthly = bill(100, at: "2026-02-28T09:00:00Z", frequency: .monthly,
                           end: "2026-03-30T23:00:00Z", start: "2026-01-31T09:00:00Z")
        let summary = try state(month: date("2026-03-01T00:00:00Z"), now: date("2026-02-10T12:00:00Z"), spent: 0)
        let result = try XCTUnwrap(PlannedBillsSummary.calculate(summary: summary, transactions: [], upcoming: [monthly]) { amount, _ in amount })
        // The March bill is March 31, after the end date, rather than drifting to March 28.
        XCTAssertEqual(result.planned, 0)
        XCTAssertEqual(summary.daysRemaining, 31)
    }

    func testPastMonthsAndLastDayHaveNoDailyDivision() throws {
        for current in [date("2026-09-30T12:00:00Z"), date("2026-10-01T12:00:00Z")] {
            let summary = try state(month: now, now: current, spent: 100)
            let result = try XCTUnwrap(PlannedBillsSummary.calculate(summary: summary, transactions: [], upcoming: []) { amount, _ in amount })
            XCTAssertNil(result.dailyAmount)
            XCTAssertNil(result.dailyRange)
        }
    }

    func testShortfallStaysVisibleWhileDailyAllowanceStopsAtZero() throws {
        let result = try forecast(spent: 19500, bills: [bill(600, at: "2026-09-16T09:00:00Z")])
        XCTAssertEqual(result.afterBills, -100)
        XCTAssertEqual(result.dailyAmount, 0)
    }

    func testOnlyExpensesCountAndMissingBillExchangeRateDoesNotShowFalseRemainder() throws {
        let summary = try state(month: now, now: now, spent: 0)
        let income = bill(100, at: "2026-09-16T09:00:00Z", kind: .income)
        let expense = bill(10, at: "2026-09-16T09:00:00Z", currency: "EUR")
        XCTAssertNil(PlannedBillsSummary.calculate(summary: summary, transactions: [], upcoming: [expense]) { _, _ in nil })
        let result = try XCTUnwrap(PlannedBillsSummary.calculate(summary: summary, transactions: [], upcoming: [income, expense]) { amount, currency in
            currency == "EUR" ? amount * 2 : amount
        })
        XCTAssertEqual(result.planned, 20)
    }

    func testParentAndChildCategoriesContributeOnceToTheirPool() throws {
        let parent = category("Food")
        let child = category("Groceries", parentID: parent.id)
        let poolID = UUID()
        let budget = MonthlyBudget(id: UUID(), accountId: nil, month: "2026-09", currency: "USD", monthlyLimit: nil,
            groups: [BudgetGroup(id: poolID, name: "Essentials", limit: "500", sortOrder: 0)],
            categoryAssignments: [BudgetCategoryAssignment(categoryId: parent.id, groupId: poolID, limit: "400"),
                                  BudgetCategoryAssignment(categoryId: child.id, groupId: poolID, limit: "200")],
            createdAt: now, updatedAt: now)
        let rows = [transaction(75, at: "2026-09-15T09:00:00Z", category: child)]
        XCTAssertEqual(BudgetLimitProgress.pools(budget: budget, transactions: rows).first?.spent, 75)
        let limits = BudgetLimitProgress.categories(budget: budget, transactions: rows, categories: [parent, child])
        XCTAssertEqual(limits.count, 2)
        XCTAssertTrue(limits.allSatisfy { $0.spent == 75 })

        let childPoolID = UUID()
        let splitBudget = MonthlyBudget(id: budget.id, accountId: nil, month: budget.month, currency: budget.currency,
            monthlyLimit: nil, groups: budget.groups + [BudgetGroup(id: childPoolID, name: "Groceries", limit: "100", sortOrder: 1)],
            categoryAssignments: [BudgetCategoryAssignment(categoryId: parent.id, groupId: poolID, limit: nil),
                                  BudgetCategoryAssignment(categoryId: child.id, groupId: childPoolID, limit: nil)],
            createdAt: now, updatedAt: now)
        let pools = BudgetLimitProgress.pools(budget: splitBudget, transactions: rows)
        XCTAssertEqual(pools.map(\.spent), [0, 75])
    }

    @MainActor
    func testOverviewComponentsRenderAtNarrowAndAccessibilitySizes() async throws {
        let summary = try state(month: now, now: now, spent: 10033)
        let planned = try forecast(spent: 10033, bills: [bill(6300, at: "2026-09-16T09:00:00Z")])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let view = NavigationStack {
                    VStack(spacing: 16) {
                        FinancePageHeader(title: "Overview", dateSelection: .constant(FinanceDateFilter(anchor: now)))
                        MonthlySummaryCompactView(state: summary, showsPlannedBills: true, plannedBills: planned)
                        FinanceMetricCards(first: .init(title: "Income", amount: 30000),
                                           second: .init(title: "Net", amount: 19967, signed: true), currency: "RUB")
                    }
                    .financeOverviewToolbar()
                }
                .environmentObject(AccountStore.preview(accounts: []))
                .environmentObject(TransactionStore())
                .padding(16)
                .environment(\.dynamicTypeSize, size)
                .preferredColorScheme(scheme)
                .background(Color(uiColor: .systemGroupedBackground))
                let controller = UIHostingController(rootView: view)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 320, height: size.isAccessibilitySize ? 1500 : 640)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                try await Task.sleep(for: .milliseconds(150))
                controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Finance-overview-\(scheme)-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }

    @MainActor
    func testUnifiedDashboardCardLayouts() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "HomeCardLayoutTests"))
        defer { defaults.removePersistentDomain(forName: "HomeCardLayoutTests") }
        defaults.set(false, forKey: AppPreferences.roundTotalsKey)
        let samples: [(String, Decimal, Decimal, Decimal?, Decimal, String)] = [
            ("budget", 3540, 1276, 2400, Decimal(string: "1386.96")!, "USD"),
            ("no-budget", 3540, 1276, nil, 1387, "USD"),
            ("empty", 0, 0, nil, 0, "USD"),
            ("income-only", 3540, 0, nil, 100, "USD"),
            ("spent-only", 0, 1276, nil, 1000, "USD"),
            ("zero-net", 1276, 1276, nil, 1276, "USD"),
            ("over-budget", 500, 2800, 2400, 1400, "USD"),
            ("budget-empty", 0, 0, 2400, 0, "USD"),
            ("large-currency", 1800000, 17116, 10000, 19000, "KZT"),
            ("large-ruble", Decimal(string: "18973175.02")!, Decimal(string: "298163.16")!,
             Decimal(string: "22767.81")!, 0, "RUB")
        ]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for roundTotals in [false, true] {
            defaults.set(roundTotals, forKey: AppPreferences.roundTotalsKey)
            for scheme in [ColorScheme.light, .dark] {
                for (name, income, spent, limit, previous, currency) in samples {
                    for width in [CGFloat(320), 393] {
                        let view = DashboardSummaryCard(
                            insights: DashboardInsights(income: income, spent: spent, previousSpent: previous,
                                                        net: income - spent, monthlyLimit: limit),
                            currency: currency, budgetTimeRemaining: limit == nil ? nil : "25 days left",
                            onViewBudget: {}, onViewMetric: { _ in }
                        )
                        .defaultAppStorage(defaults)
                        .padding(16)
                        .frame(width: width)
                        .environment(\.locale, Locale(identifier: "en_US"))
                        .preferredColorScheme(scheme)
                        .transaction { $0.disablesAnimations = true }
                        .background(LinearGradient(colors: [AppColor.accent.opacity(0.3), AppColor.groupedBackground], startPoint: .top, endPoint: .bottom))
                        .fixedSize(horizontal: false, vertical: true)
                        .ignoresSafeArea()
                        let controller = UIHostingController(rootView: view)
                        let window = UIWindow(windowScene: scene)
                        window.rootViewController = controller
                        window.makeKeyAndVisible()
                        let size = controller.sizeThatFits(in: CGSize(width: width, height: 2000))
                        XCTAssertEqual(size.width, width, accuracy: 1)
                        XCTAssertLessThan(size.height, 620, "\(name) must fit on a small phone")
                        window.frame = CGRect(origin: .zero, size: size)
                        controller.view.frame = window.bounds
                        try await Task.sleep(for: .milliseconds(350))
                        controller.view.layoutIfNeeded()
                        autoreleasepool {
                            let image = UIGraphicsImageRenderer(size: size).image { _ in
                                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                            }
                            let attachment = XCTAttachment(image: image)
                            attachment.name = "Unified-\(name)-\(Int(width))-\(scheme)-\(roundTotals ? "rounded" : "decimal")"
                            attachment.lifetime = .keepAlways
                            add(attachment)
                        }
                        window.isHidden = true
                        window.rootViewController = nil
                    }
                }
            }
        }
    }

    @MainActor
    func testUnifiedCardAccessibilityLayout() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            let controller = UIHostingController(rootView: DashboardSummaryCard(
                insights: DashboardInsights(income: 3540, spent: 1276, previousSpent: 1387,
                                            net: 2264, monthlyLimit: 2400),
                currency: "USD", budgetTimeRemaining: "25 days left",
                onViewBudget: {}, onViewMetric: { _ in }
            )
            .padding(16)
            .frame(width: 320)
            .environment(\.dynamicTypeSize, .accessibility3)
            .preferredColorScheme(scheme)
            .transaction { $0.disablesAnimations = true }
            .background(LinearGradient(colors: [AppColor.accent.opacity(0.3), AppColor.groupedBackground], startPoint: .top, endPoint: .bottom))
            .fixedSize(horizontal: false, vertical: true)
            .ignoresSafeArea())
            let window = UIWindow(windowScene: scene)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            let size = controller.sizeThatFits(in: CGSize(width: 320, height: 3000))
            XCTAssertEqual(size.width, 320, accuracy: 1)
            XCTAssertGreaterThan(size.height, 400)
            XCTAssertLessThan(size.height, 2000)
            window.frame = CGRect(origin: .zero, size: size)
            controller.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(350))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Unified-accessibility-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    private struct SummaryMetricFramesKey: PreferenceKey {
        static let defaultValue: [DashboardSummaryMetrics.Metric: CGRect] = [:]
        static func reduce(value: inout [DashboardSummaryMetrics.Metric: CGRect],
                           nextValue: () -> [DashboardSummaryMetrics.Metric: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    @MainActor
    func testSummaryMetricsKeepEqualColumnsAtPhoneWidths() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let insights = DashboardInsights(income: Decimal(string: "18973175.02")!,
                                         spent: Decimal(string: "298163.16")!, previousSpent: 0,
                                         net: Decimal(string: "18675011.86")!,
                                         monthlyLimit: Decimal(string: "22767.81")!)
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            for width in [CGFloat(248), 256, 329, 356] {
                var frames: [DashboardSummaryMetrics.Metric: CGRect] = [:]
                let view = DashboardSummaryMetrics(insights: insights, currency: "RUB")
                    .overlayPreferenceValue(DashboardSummaryMetrics.BoundsKey.self) { anchors in
                        GeometryReader { proxy in
                            Color.clear.preference(key: SummaryMetricFramesKey.self, value: anchors.mapValues {
                                $0.reduce(CGRect.null) { $0.union(proxy[$1]) }
                            })
                        }
                    }
                    .onPreferenceChange(SummaryMetricFramesKey.self) { frames = $0 }
                    .environment(\.layoutDirection, direction)
                    .environment(\.dynamicTypeSize, .large)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .ignoresSafeArea()
                let controller = UIHostingController(rootView: view)
                let window = UIWindow(windowScene: scene)
                window.rootViewController = controller
                let size = controller.sizeThatFits(in: CGSize(width: width, height: 1000))
                window.frame = CGRect(origin: .zero, size: size)
                controller.view.frame = window.bounds
                window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(100))
                controller.view.layoutIfNeeded()
                if direction == .rightToLeft {
                    frames = frames.mapValues { CGRect(x: width - $0.maxX, y: $0.minY, width: $0.width, height: $0.height) }
                }
                let net = try XCTUnwrap(frames[.net])
                let income = try XCTUnwrap(frames[.income])
                let spent = try XCTUnwrap(frames[.spent])
                XCTAssertLessThan(size.height, 70, "Standard-size metrics must stay in one compact row.")
                XCTAssertEqual(net.minX, 0, accuracy: 1)
                XCTAssertEqual(spent.maxX, width, accuracy: 1)
                XCTAssertEqual(net.minY, income.minY, accuracy: 1)
                XCTAssertEqual(income.minY, spent.minY, accuracy: 1)
                XCTAssertEqual(net.width, income.width, accuracy: 1)
                XCTAssertEqual(income.width, spent.width, accuracy: 1)
                XCTAssertEqual(income.minX - net.maxX, AppSpacing.large, accuracy: 1)
                XCTAssertEqual(spent.minX - income.maxX, AppSpacing.large, accuracy: 1)
                for frame in [net, income, spent] {
                    XCTAssertGreaterThanOrEqual(frame.width, 44)
                    XCTAssertGreaterThanOrEqual(frame.height, 44)
                }
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }

    @MainActor
    func testDashboardCardWithScreenshotAmountsInContext() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DashboardCardSpacingTests"))
        defer { defaults.removePersistentDomain(forName: "DashboardCardSpacingTests") }
        defaults.set(true, forKey: AppPreferences.roundTotalsKey)
        let insights = DashboardInsights(income: 100_000_000, spent: 1_571_034, previousSpent: 0,
                                         net: 98_428_966, monthlyLimit: 5_856_120)
        let gym = TransactionCategory(id: UUID(), systemKey: nil, name: "Gym", kind: .expense,
                                      icon: "gym", color: .lime, isSystem: false, examples: nil,
                                      sortOrder: nil, createdAt: now, updatedAt: now)
        let reminder = UpcomingTransaction(id: UUID(), accountId: accountID, kind: .expense,
                                            amount: "20000", currency: "KZT", category: gym,
                                            merchant: nil, payee: nil, note: "17:35", frequency: .daily,
                                            occurredAt: now.addingTimeInterval(86_400))
        let groceries = TransactionCategory(id: UUID(), systemKey: nil, name: "Groceries", kind: .expense,
                                            icon: "cart", color: .green, isSystem: false, examples: nil,
                                            sortOrder: nil, createdAt: now, updatedAt: now)
        let account = Account(id: accountID, name: "T Bank", type: .checking, currency: "RUB",
                              icon: "bank", iconColor: .orange, createdAt: "", updatedAt: "")
        let purchase = FinanceTransaction(id: UUID(), accountId: accountID, kind: .expense,
                                          amount: "286", currency: "RUB", category: groceries,
                                          note: "Там сям туда сюда туда сюда киреешки Там сям туда сюда туда сюда киреешки",
                                          occurredAt: now, createdAt: now, updatedAt: now)
        for scheme in [ColorScheme.light, .dark] {
            for width in [CGFloat(320), 393] {
                for enabled in [true, false] {
                    let view = VStack(alignment: .leading, spacing: AppSpacing.large) {
                        DashboardSummaryCard(insights: insights, currency: "KZT",
                                             onViewBudget: {}, onViewMetric: { _ in })
                            .disabled(!enabled)
                        DashboardUpcomingReminder(transaction: reminder, count: 1, now: now)
                        Text("4 September 2026")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppSpacing.large)
                            .padding(.top, AppSpacing.small)
                        TransactionRow(transaction: purchase, account: account)
                            .padding(AppSpacing.large)
                            .background(AppColor.elevatedSurface,
                                        in: RoundedRectangle(cornerRadius: AppRadius.extraLarge))
                    }
                    .padding(AppSpacing.large)
                    .frame(width: width)
                    .defaultAppStorage(defaults)
                    .environment(\.dynamicTypeSize, .large)
                    .preferredColorScheme(scheme)
                    .background(LinearGradient(colors: [AppColor.accent.opacity(0.18), AppColor.groupedBackground],
                                               startPoint: .top, endPoint: .center))
                    .fixedSize(horizontal: false, vertical: true)
                    .ignoresSafeArea()
                    let controller = UIHostingController(rootView: view)
                    let window = UIWindow(windowScene: scene)
                    window.rootViewController = controller
                    window.makeKeyAndVisible()
                    let size = controller.sizeThatFits(in: CGSize(width: width, height: 2000))
                    XCTAssertEqual(size.width, width, accuracy: 1)
                    XCTAssertLessThan(size.height, 700)
                    window.frame = CGRect(origin: .zero, size: size)
                    controller.view.frame = window.bounds
                    try await Task.sleep(for: .milliseconds(350))
                    controller.view.layoutIfNeeded()
                    let image = UIGraphicsImageRenderer(size: size).image { _ in
                        XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Dashboard-spacing-\(Int(width))-\(scheme)-\(enabled ? "enabled" : "disabled")"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    window.isHidden = true
                    window.rootViewController = nil
                }
            }
        }
    }

    private func forecast(spent: Decimal, bills: [UpcomingTransaction], transactions: [FinanceTransaction] = []) throws -> PlannedBillsSummary {
        let summary = try state(month: now, now: now, spent: spent)
        return try XCTUnwrap(PlannedBillsSummary.calculate(summary: summary, transactions: transactions, upcoming: bills) { amount, _ in amount })
    }
    private func state(month: Date, now: Date, spent: Decimal) throws -> MonthlySummaryState {
        let interval = try XCTUnwrap(calendar.dateInterval(of: .month, for: month))
        return try XCTUnwrap(MonthlySummaryState(monthlyBudget: 20000, amountSpent: spent, currentDate: now,
            startOfMonth: interval.start, endOfMonth: interval.end, currency: "USD", locale: Locale(identifier: "en_US"), calendar: calendar))
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func transaction(_ amount: Decimal, at: String, category: TransactionCategory? = nil) -> FinanceTransaction {
        FinanceTransaction(id: UUID(), accountId: accountID, kind: .expense,
                           amount: NSDecimalNumber(decimal: amount).stringValue, currency: "USD",
                           category: category, merchant: "Café", note: nil, occurredAt: date(at), createdAt: date(at), updatedAt: date(at))
    }
    private func bill(_ amount: Decimal, at: String, frequency: RecurrenceFrequency = .monthly, kind: TransactionKind = .expense,
                      end: String? = nil, start: String? = nil, currency: String = "USD") -> UpcomingTransaction {
        UpcomingTransaction(id: UUID(), accountId: accountID, kind: kind,
                            amount: NSDecimalNumber(decimal: amount).stringValue, currency: currency,
                            category: nil, merchant: nil, payee: nil, note: nil, frequency: frequency,
                            occurredAt: date(at), endAt: end.map(date), startAt: start.map(date))
    }
    private func category(_ name: String, parentID: UUID? = nil) -> TransactionCategory {
        TransactionCategory(id: UUID(), systemKey: nil, name: name, kind: .expense, parentId: parentID,
                            isSystem: false, examples: nil, sortOrder: nil, createdAt: now, updatedAt: now)
    }
}



// Date-filter header and finance page visual verification.
extension FinanceOverviewTests {
    @MainActor
    func testInlineDatePlacementVisualQA() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let ranges = [FinanceDateFilter(), FinanceDateFilter(preset: .allTime),
                              FinanceDateFilter(preset: .custom, anchor: now, customEnd: now.addingTimeInterval(400 * 86400))]
                let content = VStack(spacing: 20) {
                    ForEach(ranges.indices, id: \.self) { index in
                        FinancePageHeader(title: "Overview", dateSelection: .constant(ranges[index]))
                    }
                }
                .padding(20)
                .frame(width: 320)
                .environment(\.dynamicTypeSize, size)
                .preferredColorScheme(scheme)
                .background(Color(uiColor: .systemGroupedBackground))
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(windowScene: scene)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                let measured = controller.sizeThatFits(in: CGSize(width: 320, height: 1800))
                window.frame = CGRect(origin: .zero, size: measured)
                controller.view.frame = window.bounds
                try await Task.sleep(for: .milliseconds(300))
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Inline-date-states-\(scheme)-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
        let accountID = UUID()
        let currency = UserDefaults.standard.string(forKey: AppPreferences.defaultCurrencyKey) ?? AppPreferences.initialCurrency
        let account = Account(id: accountID, name: "Everyday card", type: .cash, currency: currency, icon: "wallet", iconColor: .orange, createdAt: "", updatedAt: "")
        let transactions = (0..<30).map { index in
            FinanceTransaction(id: UUID(), accountId: accountID, kind: index == 0 ? .income : .expense, amount: index == 0 ? "5000" : "25", currency: currency, category: nil, merchant: "Coffee \(index)", note: nil, occurredAt: .now, createdAt: .now, updatedAt: .now)
        }
        let accounts = AccountStore.preview(accounts: [account])
        let store = TransactionStore.preview(transactions: transactions)
        let budget = BudgetStore.preview(MonthlyBudget(id: UUID(), accountId: nil, month: BudgetMonth.key(for: .now), currency: currency, monthlyLimit: "3000", groups: [], categoryAssignments: [], createdAt: .now, updatedAt: .now))
        func scrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        for scheme in [ColorScheme.light, .dark] {
            for (name, page) in [("Home", AnyView(MainView())), ("Budget", AnyView(NavigationStack { PlanView() })), ("Settings", AnyView(NavigationStack { SettingsView() }))] {
                let content = page.environmentObject(accounts).environmentObject(store).environmentObject(budget).environmentObject(ExchangeRateStore()).preferredColorScheme(scheme)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(windowScene: scene)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                try await Task.sleep(for: .milliseconds(500))
                controller.view.layoutIfNeeded()
                let scroll = try XCTUnwrap(scrollView(in: controller.view))
                for offset in [CGFloat(0)] {
                    scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top + offset), animated: false)
                    try await Task.sleep(for: .milliseconds(300))
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Inline-date-\(name)-\(scheme)-\(Int(offset))"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }
}
