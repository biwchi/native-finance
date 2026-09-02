import XCTest
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
    func testExchangeRateStoreRequestsReportingAndAccountCurrencies() async throws {
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
            XCTAssertEqual(items?.first { $0.name == "currencies" }?.value, "EUR,KZT")
            return (200, try self.encode(response))
        }
        defer { session.invalidateAndCancel() }

        let store = ExchangeRateStore(
            apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session)
        )
        await store.load(currencies: ["EUR"], reportingCurrency: "KZT")

        XCTAssertEqual(store.state, .loaded)
        XCTAssertTrue(store.supports(["EUR", "KZT"], reportingCurrency: "KZT"))
        XCTAssertEqual(
            store.convert(100, from: "EUR", to: "KZT"),
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

    @MainActor
    func testBudgetStoreSavesLayeredBudgetPayload() async throws {
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
            XCTAssertEqual(json["month"] as? String, "2026-09")
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

        let store = BudgetStore(
            apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session)
        )
        let saved = try await store.saveBudget(
            MonthlyBudgetRequest(
                month: "2026-09",
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
        XCTAssertEqual(store.budget, responseBudget)
        XCTAssertEqual(store.state, .loaded)
    }

    private func budget(accountID: UUID, groupID: UUID, categoryID: UUID) -> MonthlyBudget {
        MonthlyBudget(
            id: UUID(),
            accountId: accountID,
            month: "2026-09",
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
