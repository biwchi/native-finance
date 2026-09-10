import XCTest
@testable import FinanceTracker

actor TestRateTransport: RateTransport {
    var calls = 0
    var fails = false
    func setFailure(_ value: Bool) { fails = value }
    func fullExchangeRateTable() async throws -> ExchangeRateSnapshot {
        calls += 1
        try await Task.sleep(for: .milliseconds(20))
        if fails { throw URLError(.notConnectedToInternet) }
        return ExchangeRateSnapshot(baseCurrency: "USD", reportingCurrency: "USD", quotes: [ExchangeRateQuote(currency: "EUR", rate: "0.8", effectiveDate: "2026-01-01"), ExchangeRateQuote(currency: "KZT", rate: "500", effectiveDate: "2026-01-01")], fetchedAt: LocalTestData.now, stale: false)
    }
}
@MainActor
final class DailyRateTests: XCTestCase {
    func testConcurrentScreensAndNewDisplayCurrencyShareOneFullRequest() async throws {
        let repository = try LocalTestData.repository(); let transport = TestRateTransport()
        let service = DailyRateService(repository: repository, transport: transport)
        async let first: Void = service.refreshIfNeeded(now: LocalTestData.now)
        async let second: Void = service.refreshIfNeeded(now: LocalTestData.now)
        _ = await (first, second)
        await service.refreshIfNeeded(now: LocalTestData.now.addingTimeInterval(100))
        let count = await transport.calls; XCTAssertEqual(count, 1)
        let one = ExchangeRateStore(repository: repository, service: service); let two = ExchangeRateStore(repository: repository, service: service)
        XCTAssertEqual(one.convert(100, from: "EUR", to: "USD"), 125)
        XCTAssertEqual(two.convert(100, from: "EUR", to: "KZT"), 62500)
        XCTAssertEqual(one.state, .loaded); XCTAssertNil(two.convert(100, from: "JPY", to: "USD"))
    }
    func testDailyCacheSurvivesRestartAndExpirationFailureDoesNotAdvanceFreshness() async throws {
        let repository = try LocalTestData.repository(); let transport = TestRateTransport()
        await DailyRateService(repository: repository, transport: transport).refreshIfNeeded(now: LocalTestData.now)
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        let service = DailyRateService(repository: reopened, transport: transport)
        await service.refreshIfNeeded(now: LocalTestData.now.addingTimeInterval(86399))
        var calls = await transport.calls; XCTAssertEqual(calls, 1)
        await transport.setFailure(true)
        await service.refreshIfNeeded(now: LocalTestData.now.addingTimeInterval(86400))
        calls = await transport.calls; XCTAssertEqual(calls, 2)
        XCTAssertEqual(try reopened.value(Date.self, key: "ratesRefreshedAt"), LocalTestData.now)
        XCTAssertEqual(reopened.snapshot.rates?.convert(100, from: "EUR", to: "USD"), 125)
        await transport.setFailure(false)
        await service.refreshIfNeeded(now: LocalTestData.now.addingTimeInterval(86500))
        calls = await transport.calls; XCTAssertEqual(calls, 3)
        XCTAssertEqual(try reopened.value(Date.self, key: "ratesRefreshedAt"), LocalTestData.now.addingTimeInterval(86500))
    }
}
