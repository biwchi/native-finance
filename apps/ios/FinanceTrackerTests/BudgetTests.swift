import XCTest
import SwiftUI
@testable import FinanceTracker

final class BudgetTests: XCTestCase {
    func testExchangeRateSnapshotConvertsThroughCanonicalBase() throws {
        let snapshot = ExchangeRateSnapshot(
            baseCurrency: "USD",
            reportingCurrency: "KZT",
            quotes: [
                ExchangeRateQuote(currency: "EUR", rate: "0.86", effectiveDate: "2026-09-02"),
                ExchangeRateQuote(currency: "KZT", rate: "540.12", effectiveDate: "2026-09-02"),
                ExchangeRateQuote(currency: "USD", rate: "1", effectiveDate: "2026-09-02"),
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_788_350_400),
            stale: false
        )

        let converted = try XCTUnwrap(snapshot.convert(100, from: "EUR", to: "KZT"))

        XCTAssertEqual(
            NSDecimalNumber(decimal: converted).doubleValue,
            62_804.6511,
            accuracy: 0.0001
        )
        XCTAssertEqual(snapshot.convert(100, from: "KZT", to: "KZT"), 100)
    }

    @MainActor
    func testLegacyRateEndpointStillAcceptsCurrencyFilters() async throws {
        let response = ExchangeRateSnapshot(
            baseCurrency: "USD",
            reportingCurrency: "KZT",
            quotes: [
                ExchangeRateQuote(currency: "EUR", rate: "0.86", effectiveDate: "2026-09-02"),
                ExchangeRateQuote(currency: "KZT", rate: "540.12", effectiveDate: "2026-09-02"),
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_788_350_400),
            stale: false
        )
        let session = makeSession { request in
            XCTAssertEqual(request.url?.path, "/api/v1/exchange-rates/latest")
            let items = URLComponents(
                url: try XCTUnwrap(request.url),
                resolvingAgainstBaseURL: false
            )?.queryItems
            XCTAssertEqual(items?.first { $0.name == "reportingCurrency" }?.value, "KZT")
            XCTAssertEqual(items?.first { $0.name == "currencies" }?.value, "EUR")
            return (200, try self.encode(response))
        }
        defer { session.invalidateAndCancel() }

        let result = try await APIClient(baseURL: URL(string: "https://test.invalid")!, session: session).latestExchangeRates(currencies: ["EUR"], reportingCurrency: "KZT")
        XCTAssertTrue(result.supports(["EUR", "KZT"], reportingCurrency: "KZT"))
        XCTAssertEqual(
            result.convert(100, from: "EUR", to: "KZT"),
            response.convert(100, from: "EUR", to: "KZT")
        )
    }

    func testInsightsCompareCurrentMonthThroughSameDayLastMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let accountID = UUID()
        let now = try date("2026-09-10T12:00:00Z")
        let transactions = [
            transaction(accountID: accountID, kind: .income, amount: "4200", date: try date("2026-09-03T08:00:00Z")),
            transaction(accountID: accountID, kind: .expense, amount: "2000", date: try date("2026-09-05T08:00:00Z")),
            transaction(accountID: accountID, kind: .expense, amount: "999", date: try date("2026-09-20T08:00:00Z")),
            transaction(accountID: accountID, kind: .expense, amount: "2200", date: try date("2026-08-05T08:00:00Z")),
            transaction(accountID: accountID, kind: .expense, amount: "999", date: try date("2026-08-15T08:00:00Z")),
        ]

        let insights = DashboardInsights.calculate(
            transactions: transactions,
            month: now,
            now: now,
            calendar: calendar,
            monthlyLimit: 3_800
        )

        XCTAssertEqual(insights.income, 4_200)
        XCTAssertEqual(insights.spent, 2_000)
        XCTAssertEqual(insights.previousSpent, 2_200)
        XCTAssertEqual(insights.net, 2_200)
        XCTAssertEqual(insights.remaining, 1_800)
        XCTAssertEqual(insights.paceDifference, 200)
        XCTAssertEqual(
            NSDecimalNumber(decimal: try XCTUnwrap(insights.comparisonPercent)).doubleValue,
            -9.0909,
            accuracy: 0.001
        )
    }

    func testSummaryUsesPoolsAndStandaloneLimitsWithoutCountingPooledCapsTwice() {
        let poolID = UUID()
        let saved = summaryBudget(groups: [
            .init(id: poolID, name: "Needs", limit: "100.25", sortOrder: 0),
            .init(id: UUID(), name: "Fun", limit: "50.50", sortOrder: 1)
        ], assignments: [
            .init(categoryId: UUID(), groupId: poolID, limit: "80"),
            .init(categoryId: UUID(), groupId: poolID, limit: nil),
            .init(categoryId: UUID(), groupId: nil, limit: "30.75")
        ])

        XCTAssertEqual(saved.summaryLimit(), Decimal(string: "181.50"))
        XCTAssertNil(saved.summaryLimit(useAllocatedBudget: false))
        XCTAssertNil(saved.monthlyLimit, "The calculated total must not become a saved monthly limit")
    }

    func testSummarySupportsASinglePoolOrCategoryAndKeepsEmptyBudgetsHidden() {
        XCTAssertEqual(summaryBudget(groups: [
            .init(id: UUID(), name: "Needs", limit: "100", sortOrder: 0)
        ]).summaryLimit(), 100)
        XCTAssertEqual(summaryBudget(assignments: [
            .init(categoryId: UUID(), groupId: nil, limit: "75")
        ]).summaryLimit(), 75)
        XCTAssertNil(summaryBudget().summaryLimit())
        XCTAssertNil(summaryBudget(assignments: [
            .init(categoryId: UUID(), groupId: nil, limit: nil)
        ]).summaryLimit())
    }

    func testExplicitMonthlyLimitTakesPrecedenceWithEitherSummaryPreference() {
        let saved = summaryBudget(monthlyLimit: "500", groups: [
            .init(id: UUID(), name: "Needs", limit: "100", sortOrder: 0)
        ], assignments: [.init(categoryId: UUID(), groupId: nil, limit: "75")])
        XCTAssertEqual(saved.summaryLimit(), 500)
        XCTAssertEqual(saved.summaryLimit(useAllocatedBudget: false), 500)
    }

    @MainActor
    func testAllocatedSummaryUsesConvertedAmountsAndRemainsMonthly() async throws {
        let repository = try LocalTestData.repository()
        let service = DailyRateService(repository: repository, transport: TestRateTransport())
        await service.refreshIfNeeded(now: LocalTestData.now)
        let rates = ExchangeRateStore(repository: repository, service: service)
        let saved = summaryBudget(groups: [
            .init(id: UUID(), name: "Needs", limit: "100", sortOrder: 0)
        ], assignments: [.init(categoryId: UUID(), groupId: nil, limit: "25")])
        let converted = saved.converted(to: "KZT", using: rates)
        let limit = try XCTUnwrap(converted?.summaryLimit())
        XCTAssertEqual(limit, 62_500)
        let now = LocalTestData.now
        let transactions = [transaction(accountID: UUID(), kind: .expense, amount: "70000", date: now)]
        let monthly = DashboardInsights.calculate(transactions: transactions, month: now, now: now, monthlyLimit: limit)
        XCTAssertTrue(monthly.hasBudget)
        XCTAssertEqual(monthly.remaining, -7_500)
        XCTAssertGreaterThan(try XCTUnwrap(monthly.budgetProgress), 1)
        let weekly = DashboardInsights.calculate(transactions: transactions,
            filter: FinanceDateFilter(preset: .week, anchor: now), now: now, monthlyLimit: limit)
        XCTAssertFalse(weekly.hasBudget)
    }

    private func summaryBudget(
        monthlyLimit: String? = nil, groups: [BudgetGroup] = [], assignments: [BudgetCategoryAssignment] = []
    ) -> MonthlyBudget {
        MonthlyBudget(id: UUID(), accountId: nil, currency: "USD", monthlyLimit: monthlyLimit,
            groups: groups, categoryAssignments: assignments, createdAt: .now, updatedAt: .now)
    }

    @MainActor
    func testLegacyBudgetEndpointAcceptsLayeredBudgetPayload() async throws {
        let accountID = UUID()
        let groupID = UUID()
        let categoryID = UUID()
        let responseBudget = budget(
            accountID: accountID,
            groupID: groupID,
            categoryID: categoryID
        )
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/v1/budgets/monthly")
            let body = try XCTUnwrap(requestBody(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNil(json["month"])
            XCTAssertEqual(json["accountId"] as? String, accountID.uuidString)
            XCTAssertEqual(json["monthlyLimit"] as? String, "3800")

            let groups = try XCTUnwrap(json["groups"] as? [[String: Any]])
            XCTAssertEqual(groups.first?["id"] as? String, groupID.uuidString)
            XCTAssertEqual(groups.first?["name"] as? String, "Needs")

            let assignments = try XCTUnwrap(json["categoryAssignments"] as? [[String: Any]])
            XCTAssertEqual(assignments.first?["categoryId"] as? String, categoryID.uuidString)
            XCTAssertEqual(assignments.first?["groupId"] as? String, groupID.uuidString)
            XCTAssertNil(assignments.first?["limit"])
            return (200, try self.encode(responseBudget))
        }
        defer { session.invalidateAndCancel() }

        let client = APIClient(baseURL: URL(string: "https://test.invalid")!, session: session)
        let saved = try await client.saveMonthlyBudget(
            MonthlyBudgetRequest(
                accountId: accountID,
                currency: "USD",
                monthlyLimit: "3800",
                groups: [BudgetGroupRequest(id: groupID, name: "Needs", limit: "500")],
                categoryAssignments: [
                    BudgetCategoryAssignmentRequest(
                        categoryId: categoryID,
                        groupId: groupID,
                        limit: nil
                    ),
                ]
            )
        )

        XCTAssertEqual(saved, responseBudget)
    }

    @MainActor
    func testOneBudgetMeasuresCurrentPreviousAndFutureMonthsIndependently() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let category = try repository.edit { try $0.saveCategory(name: "Food", kind: .expense, parentID: nil, icon: "tag", color: .blue) }
        let groupID = UUID()
        let store = BudgetStore(repository: repository)
        let savedResult = try await store.saveBudget(MonthlyBudgetRequest(accountId: account.id, currency: "USD", monthlyLimit: "500", groups: [BudgetGroupRequest(id: groupID, name: "Needs", limit: "300")], categoryAssignments: [BudgetCategoryAssignmentRequest(categoryId: category.id, groupId: groupID, limit: "200")]))
        let saved = try XCTUnwrap(savedResult)
        for (time, amount) in [("2026-08-05T12:00:00Z", "250"), ("2026-09-05T12:00:00Z", "100")] {
            _ = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id, amount: amount, categoryID: category.id, occurredAt: LocalTestData.date(time))) }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for (month, expected) in [("2026-08-15T12:00:00Z", Decimal(250)), ("2026-09-15T12:00:00Z", Decimal(100)), ("2026-10-15T12:00:00Z", Decimal(0))] {
            let budget = try XCTUnwrap(store.budget(accountID: account.id))
            XCTAssertEqual(budget.id, saved.id)
            let expenses = FinanceOverviewData.transactions(repository.snapshot.detailedTransactions, in: LocalTestData.date(month), calendar: calendar)
            XCTAssertEqual(expenses.reduce(Decimal.zero) { $0 + (Decimal(string: $1.amount) ?? 0) }, expected)
            XCTAssertEqual(BudgetLimitProgress.pools(budget: budget, transactions: expenses).first?.remaining, 300 - expected)
            XCTAssertEqual(BudgetLimitProgress.categories(budget: budget, transactions: expenses, categories: [category]).first?.remaining, 200 - expected)
        }
        XCTAssertEqual(repository.snapshot.budgets.count, 1)
    }

    @MainActor
    func testBudgetOverviewAndSettingsRenderForPreviousMonths() async throws {
        let saved = budget(accountID: UUID(), groupID: UUID(), categoryID: UUID())
        let repository = try LocalTestData.repository()
        let budgets = BudgetStore(repository: repository)
        _ = try await budgets.saveBudget(MonthlyBudgetRequest(accountId: nil, currency: "USD", monthlyLimit: saved.monthlyLimit, groups: [], categoryAssignments: []))
        let accountStore = AccountStore.preview(accounts: [])
        let transactions = TransactionStore.preview(transactions: [])
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "GlobalBudgetRenderTests"))
        defaults.set("USD", forKey: AppPreferences.defaultCurrencyKey)
        defer { defaults.removePersistentDomain(forName: "GlobalBudgetRenderTests") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            for (name, page) in [
                ("August", AnyView(BudgetOverviewView(initialMonth: LocalTestData.date("2026-08-15T12:00:00Z")))),
                ("September", AnyView(BudgetOverviewView(initialMonth: LocalTestData.date("2026-09-15T12:00:00Z")))),
                ("Settings", AnyView(BudgetSettingsView(accountID: nil, currency: "USD", budget: budgets.budget(accountID: nil)).navigationTitle("Edit budget")))
            ] {
                let content = NavigationStack { page }
                    .environmentObject(accountStore).environmentObject(transactions).environmentObject(budgets)
                    .defaultAppStorage(defaults).preferredColorScheme(scheme)
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
                attachment.name = "GlobalBudget-\(name)-\(scheme)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }

    private func budget(accountID: UUID, groupID: UUID, categoryID: UUID) -> MonthlyBudget {
        MonthlyBudget(
            id: UUID(),
            accountId: accountID,
            currency: "USD",
            monthlyLimit: "3800.0000",
            groups: [BudgetGroup(id: groupID, name: "Needs", limit: "500.0000", sortOrder: 0)],
            categoryAssignments: [
                BudgetCategoryAssignment(categoryId: categoryID, groupId: groupID, limit: nil),
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func transaction(
        accountID: UUID,
        kind: TransactionKind,
        amount: String,
        date: Date
    ) -> FinanceTransaction {
        FinanceTransaction(
            id: UUID(),
            accountId: accountID,
            kind: kind,
            amount: amount,
            currency: "USD",
            category: nil,
            note: nil,
            occurredAt: date,
            createdAt: date,
            updatedAt: date
        )
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    nonisolated private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(value)
    }

    private func makeSession(
        handler: @escaping (URLRequest) throws -> (Int, Data)
    ) -> URLSession {
        BudgetTestProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BudgetTestProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class BudgetTestProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}
