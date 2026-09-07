import SwiftUI
import XCTest
@testable import FinanceTracker

final class FinancesOverviewTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testForecastCountsDueDatesAndKeepsIncomeSeparate() throws {
        let upcoming = [
            bill("10", frequency: .daily, at: "2026-01-01T00:00:00Z"),
            bill("100", frequency: .weekly, at: "2026-01-02T00:00:00Z"),
            bill("300", frequency: .monthly, at: "2026-01-15T00:00:00Z"),
            bill("1200", frequency: .yearly, at: "2026-02-01T00:00:00Z"),
            bill("2000", frequency: .monthly, at: "2026-01-16T00:00:00Z", kind: .income),
            bill("99999", frequency: .daily, at: "2026-01-01T00:00:00Z", kind: .debt)
        ]
        let expected: [(RecurringForecast.Period, Decimal, Decimal)] = [
            (.day, 10, 0), (.week, 170, 0), (.month, 1100, 2000), (.year, 13650, 24000)
        ]
        for (period, expenses, income) in expected {
            let result = try XCTUnwrap(RecurringForecast.calculate(
                upcoming: upcoming, period: period,
                now: date("2026-01-01T00:00:00Z"), calendar: calendar
            ) { amount, _ in amount })
            XCTAssertEqual(result.expenses, expenses, period.rawValue)
            XCTAssertEqual(result.income, income, period.rawValue)
        }
    }

    func testForecastIncludesEndDateAndExcludesWindowEnd() throws {
        let upcoming = [
            bill("25", frequency: .weekly, at: "2026-01-02T00:00:00Z", end: "2026-01-09T00:00:00Z"),
            bill("80", frequency: .yearly, at: "2026-01-31T00:00:00Z"),
            bill("999", frequency: .daily, at: "2025-12-01T00:00:00Z", end: "2025-12-02T00:00:00Z")
        ]
        let expected: [(RecurringForecast.Period, Decimal)] = [(.day, 0), (.week, 25), (.month, 50), (.year, 130)]
        for (period, expenses) in expected {
            let result = try XCTUnwrap(RecurringForecast.calculate(
                upcoming: upcoming, period: period,
                now: date("2026-01-01T00:00:00Z"), calendar: calendar
            ) { amount, _ in amount })
            XCTAssertEqual(result.expenses, expenses, period.rawValue)
        }
    }

    func testForecastPreservesMonthEndAndLeapDayAnchors() throws {
        var monthly = bill("100", frequency: .monthly, at: "2026-02-28T10:00:00Z")
        monthly.startAt = date("2026-01-31T10:00:00Z")
        XCTAssertEqual(RecurrenceSchedule.nextOccurrence(after: monthly.occurredAt, bill: monthly), date("2026-03-31T10:00:00Z"))
        var yearly = bill("100", frequency: .yearly, at: "2027-02-28T10:00:00Z")
        yearly.startAt = date("2024-02-29T10:00:00Z")
        XCTAssertEqual(RecurrenceSchedule.nextOccurrence(after: yearly.occurredAt, bill: yearly), date("2028-02-29T10:00:00Z"))
    }

    func testForecastDoesNotPublishPartialCurrencyTotals() throws {
        let upcoming = [
            bill("100", frequency: .monthly, at: "2026-01-15T00:00:00Z"),
            bill("50", frequency: .monthly, at: "2026-01-15T00:00:00Z", currency: "EUR")
        ]
        let now = date("2026-01-01T00:00:00Z")
        XCTAssertNil(RecurringForecast.calculate(upcoming: upcoming, period: .month, now: now, calendar: calendar) { amount, code in
            code == "USD" ? amount : nil
        })
        let converted = try XCTUnwrap(RecurringForecast.calculate(upcoming: upcoming, period: .month, now: now, calendar: calendar) { amount, code in
            code == "EUR" ? amount * 2 : amount
        })
        XCTAssertEqual(converted.expenses, 200)
        XCTAssertEqual(RecurringForecast.calculate(upcoming: [], period: .year, now: now, calendar: calendar) { _, _ in nil }?.expenses, 0)
        XCTAssertEqual(RecurringForecast.calculate(upcoming: upcoming, period: .day, now: now, calendar: calendar) { _, _ in nil }?.expenses, 0)
    }

    func testForecastFiltersAmountsAndOnlyRequiresRatesForIncludedTransactions() throws {
        let upcoming = [
            bill("100", frequency: .monthly, at: "2026-01-15T00:00:00Z"),
            bill("250", frequency: .monthly, at: "2026-01-15T00:00:00Z", kind: .income, currency: "EUR")
        ]
        let now = date("2026-01-01T00:00:00Z")
        let expenses = try XCTUnwrap(RecurringForecast.calculate(
            upcoming: upcoming, period: .month, filter: .expenses, now: now, calendar: calendar
        ) { amount, code in code == "USD" ? amount : nil })
        XCTAssertEqual(expenses, RecurringForecast.Totals(expenses: 100, income: 0))
        let income = try XCTUnwrap(RecurringForecast.calculate(
            upcoming: upcoming, period: .month, filter: .income, now: now, calendar: calendar
        ) { amount, code in code == "EUR" ? amount * 2 : nil })
        XCTAssertEqual(income, RecurringForecast.Totals(expenses: 0, income: 500))
        let all = try XCTUnwrap(RecurringForecast.calculate(
            upcoming: upcoming, period: .month, filter: .all, now: now, calendar: calendar
        ) { amount, code in code == "EUR" ? amount * 2 : amount })
        XCTAssertEqual(RecurringForecast.KindFilter.expenses.amount(from: all), 100)
        XCTAssertEqual(RecurringForecast.KindFilter.income.amount(from: all), 500)
        XCTAssertEqual(RecurringForecast.KindFilter.all.amount(from: all), 400)
        XCTAssertEqual(RecurringForecast.KindFilter.all.amount(from: .init(expenses: 100, income: 25)), -75)
        XCTAssertEqual(RecurringForecast.KindFilter.all.amount(from: .init(expenses: 100, income: 100)), 0)
        XCTAssertEqual(upcoming.filter { RecurringForecast.KindFilter.expenses.includes($0.kind) }.map(\.kind), [.expense])
        XCTAssertEqual(upcoming.filter { RecurringForecast.KindFilter.income.includes($0.kind) }.map(\.kind), [.income])
        XCTAssertFalse(RecurringForecast.KindFilter.all.includes(.debt))
    }

    func testPoolDrillDownHonorsChildOverridesAndIncludesCategoriesWithoutOwnLimits() throws {
        let parent = category("Food")
        let child = category("Groceries", parentID: parent.id)
        let pool = UUID()
        let otherPool = UUID()
        let now = date("2026-09-07T10:00:00Z")
        let budget = MonthlyBudget(id: UUID(), accountId: nil, month: "2026-09", currency: "USD", monthlyLimit: "500",
            groups: [BudgetGroup(id: pool, name: "Needs", limit: "200", sortOrder: 0),
                     BudgetGroup(id: otherPool, name: "Shopping", limit: "50", sortOrder: 1)],
            categoryAssignments: [BudgetCategoryAssignment(categoryId: parent.id, groupId: pool, limit: nil),
                                  BudgetCategoryAssignment(categoryId: child.id, groupId: otherPool, limit: "30")],
            createdAt: now, updatedAt: now)
        let groceries = transaction(amount: "40", category: child, at: now)
        let restaurant = transaction(amount: "20", category: parent, at: now)
        let income = transaction(amount: "900", category: child, at: now, kind: .income)
        let transactions = [groceries, restaurant, income]
        XCTAssertEqual(BudgetLimitProgress.transactions(inPool: pool, budget: budget, from: transactions).map(\.id), [restaurant.id])
        XCTAssertEqual(BudgetLimitProgress.transactions(inPool: otherPool, budget: budget, from: transactions).map(\.id), [groceries.id])
        let categories = BudgetCategorySpending.calculate(budget: budget, transactions: transactions, categories: [parent, child])
        let food = try XCTUnwrap(categories.first { $0.id == parent.id })
        XCTAssertEqual(food.spent, 60)
        XCTAssertNil(food.limit)
        XCTAssertEqual(food.poolName, "Needs")
        XCTAssertEqual(categories.first { $0.id == child.id }?.progress?.remaining, -10)
    }

    @MainActor
    func testFinancesScreensRenderInBothAppearancesAndAtAccessibilitySize() async throws {
        let now = Date.now
        let account = Account(id: UUID(), name: "Everyday", type: .checking, currency: "USD",
            icon: "credit-card", iconColor: .blue, createdAt: "", updatedAt: "")
        let groceries = category("Groceries")
        let recipient = Debt(id: UUID(), name: "Alexey", icon: "user", color: .blue)
        let pool = UUID()
        let budget = MonthlyBudget(id: UUID(), accountId: nil, month: BudgetMonth.key(for: now), currency: "USD",
            monthlyLimit: "1200", groups: [BudgetGroup(id: pool, name: "Essentials", limit: "600", sortOrder: 0)],
            categoryAssignments: [BudgetCategoryAssignment(categoryId: groceries.id, groupId: pool, limit: "250")],
            createdAt: now, updatedAt: now)
        let loan = FinanceTransaction(id: UUID(), accountId: account.id, kind: .debt, amount: "125.50", currency: "USD",
            category: nil, note: "Dinner", occurredAt: now, createdAt: now, updatedAt: now, debtId: recipient.id, debt: recipient)
        let schedule = UpcomingTransaction(id: UUID(), accountId: account.id, kind: .expense, amount: "45", currency: "USD",
            category: groceries, merchant: "Groceries", payee: nil, note: nil, frequency: .weekly, occurredAt: now.addingTimeInterval(3600))
        let salary = UpcomingTransaction(id: UUID(), accountId: account.id, kind: .income, amount: "1800", currency: "USD",
            category: nil, merchant: nil, payee: "Salary", note: nil, frequency: .monthly, occurredAt: now.addingTimeInterval(7200))
        var expense = FinanceTransaction(id: UUID(), accountId: account.id, kind: .expense, amount: "275.30", currency: "USD",
            category: groceries, merchant: "Groceries", note: nil, occurredAt: now.addingTimeInterval(-60), createdAt: now, updatedAt: now)
        expense.recurrence = schedule.recurrence
        var income = FinanceTransaction(id: UUID(), accountId: account.id, kind: .income, amount: "1800", currency: "USD",
            category: nil, payee: "Salary", note: nil, occurredAt: now.addingTimeInterval(-120), createdAt: now, updatedAt: now)
        income.recurrence = salary.recurrence
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewProtocol.self]
        PreviewProtocol.responses = ["transactions": try encode([expense, income, loan]), "upcoming": try encode([schedule, salary]),
            "debts": try encode([recipient]), "categories": try encode([groceries]), "monthly": try encode(budget)]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); PreviewProtocol.responses = [:] }
        let api = APIClient(baseURL: URL(string: "https://test.invalid")!, session: session)
        let store = TransactionStore(apiClient: api)
        await store.loadTransactions(accountID: nil)
        await store.loadCategories()
        let budgets = BudgetStore(apiClient: api)
        await budgets.loadBudget(month: now, accountID: nil)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FinancesOverviewRenderTests"))
        defaults.set("USD", forKey: AppPreferences.defaultCurrencyKey)
        defer { defaults.removePersistentDomain(forName: "FinancesOverviewRenderTests") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                for (name, page) in [
                    ("Home", AnyView(DashboardView())),
                    ("Hub", AnyView(FinancesView())),
                    ("Recurring", AnyView(RecurringTransactionsView(allAccounts: true))),
                    ("Debts", AnyView(DebtsView())),
                    ("Budget", AnyView(BudgetOverviewView()))
                ] {
                    let displayed: AnyView
                    if name == "Home" {
                        displayed = page
                    } else {
                        displayed = AnyView(NavigationStack(path: .constant([1])) {
                            Color.clear
                                .navigationTitle(name == "Hub" ? "Home" : "Finances")
                                .navigationDestination(for: Int.self) { _ in page }
                        })
                    }
                    let content = displayed
                        .environmentObject(AccountStore.preview(accounts: [account]))
                        .environmentObject(store).environmentObject(budgets)
                        .defaultAppStorage(defaults)
                        .environment(\.dynamicTypeSize, size)
                        .preferredColorScheme(scheme)
                    let controller = UIHostingController(rootView: content)
                    let window = UIWindow(windowScene: scene)
                    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                    window.rootViewController = controller
                    window.makeKeyAndVisible()
                    controller.view.frame = window.bounds
                    try await Task.sleep(for: .milliseconds(300))
                    controller.view.layoutIfNeeded()
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Finances-\(name)-\(scheme)-\(size)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    if name == "Recurring" {
                        let initialControls = segmentedControls(in: controller.view)
                        XCTAssertEqual(initialControls.first { $0.numberOfSegments == 3 }?.selectedSegmentIndex, 0)
                        XCTAssertEqual(initialControls.first { $0.numberOfSegments == 4 }?.selectedSegmentIndex, 2)
                        for (kind, period, label) in [
                            (0, 0, "Expenses-Day"), (0, 1, "Expenses-Week"), (0, 3, "Expenses-Year"),
                            (1, 2, "Income-Month"), (2, 2, "All-Month")
                        ] {
                            let controls = segmentedControls(in: controller.view)
                            let kindControl = try XCTUnwrap(controls.first { $0.numberOfSegments == 3 })
                            let periodControl = try XCTUnwrap(controls.first { $0.numberOfSegments == 4 })
                            kindControl.selectedSegmentIndex = kind
                            kindControl.sendActions(for: .valueChanged)
                            periodControl.selectedSegmentIndex = period
                            periodControl.sendActions(for: .valueChanged)
                            try await Task.sleep(for: .seconds(2))
                            controller.view.layoutIfNeeded()
                            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                            }
                            let attachment = XCTAttachment(image: image)
                            attachment.name = "Finances-Recurring-\(label)-\(scheme)-\(size)"
                            attachment.lifetime = .keepAlways
                            add(attachment)
                        }
                    }
                    window.isHidden = true
                }
            }
        }
    }

    @MainActor
    private func segmentedControls(in view: UIView) -> [UISegmentedControl] {
        (view as? UISegmentedControl).map { [$0] } ?? view.subviews.flatMap { segmentedControls(in: $0) }
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func bill(_ amount: String, frequency: RecurrenceFrequency, at: String, end: String? = nil,
                      kind: TransactionKind = .expense, currency: String = "USD") -> UpcomingTransaction {
        UpcomingTransaction(id: UUID(), accountId: UUID(), kind: kind, amount: amount, currency: currency,
            category: nil, merchant: nil, payee: nil, note: nil, frequency: frequency, occurredAt: date(at), endAt: end.map(date))
    }
    private func category(_ name: String, parentID: UUID? = nil) -> TransactionCategory {
        TransactionCategory(id: UUID(), systemKey: nil, name: name, kind: .expense, parentId: parentID,
            icon: "cart", color: .green, isSystem: false, examples: nil, sortOrder: nil, createdAt: nil, updatedAt: nil)
    }
    private func transaction(amount: String, category: TransactionCategory, at: Date, kind: TransactionKind = .expense) -> FinanceTransaction {
        FinanceTransaction(id: UUID(), accountId: UUID(), kind: kind, amount: amount, currency: "USD", category: category,
            note: nil, occurredAt: at, createdAt: at, updatedAt: at)
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private final class PreviewProtocol: URLProtocol {
        static var responses: [String: Data] = [:]
        override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "test.invalid" }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let data = Self.responses[request.url?.lastPathComponent ?? ""] ?? Data("[]".utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
