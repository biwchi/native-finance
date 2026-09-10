import Foundation

@MainActor
final class DailyRateService {
    static let shared = DailyRateService(repository: .shared, transport: APIClient())
    private let repository: LocalFinanceRepository
    private let transport: any RateTransport
    private var request: Task<Void, Never>?
    private var retryAfter = Date.distantPast
    init(repository: LocalFinanceRepository, transport: any RateTransport) { self.repository = repository; self.transport = transport }
    func refreshIfNeeded(now: Date = .now) async {
        if let request { await request.value; return }
        guard now >= retryAfter else { return }
        if let last = try? repository.value(Date.self, key: "ratesRefreshedAt"), now.timeIntervalSince(last) < 24 * 60 * 60, repository.snapshot.rates != nil { return }
        let task = Task {
            do {
                let rates = try await transport.fullExchangeRateTable()
                guard rates.baseCurrency == "USD", !rates.quotes.isEmpty else { throw APIClientError.invalidResponse }
                try repository.saveRates(rates, refreshedAt: rates.stale ? nil : now)
                if rates.stale { retryAfter = now.addingTimeInterval(60) }
            } catch { retryAfter = now.addingTimeInterval(60) }
        }
        request = task; await task.value; request = nil
    }
}
