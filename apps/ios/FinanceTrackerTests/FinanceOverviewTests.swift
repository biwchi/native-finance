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
                        FinancePageHeader(title: "Overview")
                        MonthlySummaryCompactView(state: summary, showsPlannedBills: true, plannedBills: planned)
                        FinanceMetricCards(first: .init(title: "Income", amount: 30000),
                                           second: .init(title: "Net", amount: 19967, signed: true), currency: "RUB")
                    }
                    .financeMonthPickerToolbar(month: .constant(now))
                }
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
