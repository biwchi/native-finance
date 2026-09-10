import Combine
import Foundation

@MainActor
final class ExchangeRateStore: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var state: State = .loaded
    @Published private(set) var snapshot: ExchangeRateSnapshot?
    private let service: DailyRateService
    private var subscription: AnyCancellable?
    init(apiClient: APIClient = APIClient(), repository: LocalFinanceRepository? = nil, service: DailyRateService? = nil) {
        let repository = repository ?? .shared
        self.service = service ?? DailyRateService.shared
        snapshot = repository.snapshot.rates
        subscription = repository.$snapshot.map(\.rates).removeDuplicates().sink { [weak self] in self?.snapshot = $0 }
    }
    func load(currencies: Set<String>, reportingCurrency: String, force: Bool = false) async {
        // Currency selection and legacy force callers use the same daily table.
        await service.refreshIfNeeded()
    }
    func convert(_ amount: Decimal, from sourceCurrency: String, to reportingCurrency: String) -> Decimal? {
        sourceCurrency.caseInsensitiveCompare(reportingCurrency) == .orderedSame ? amount : snapshot?.convert(amount, from: sourceCurrency, to: reportingCurrency)
    }
    func supports(_ currencies: Set<String>, reportingCurrency: String) -> Bool {
        currencies.allSatisfy { $0.caseInsensitiveCompare(reportingCurrency) == .orderedSame } || snapshot?.supports(currencies, reportingCurrency: reportingCurrency) == true
    }
}
