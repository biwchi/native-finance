import Combine
import Foundation

@MainActor
final class ExchangeRateStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot: ExchangeRateSnapshot?

    private let apiClient: APIClient
    private var currentScope = ""

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func load(
        currencies: Set<String>,
        reportingCurrency: String,
        force: Bool = false
    ) async {
        let reporting = reportingCurrency.uppercased()
        let normalized = Set(currencies.map { $0.uppercased() }).union([reporting])
        let scope = "\(reporting):\(normalized.sorted().joined(separator: ","))"
        if !force,
           scope == currentScope,
           state == .loaded || state == .loading {
            return
        }

        currentScope = scope
        if normalized.allSatisfy({ $0 == reporting }) {
            snapshot = nil
            state = .loaded
            return
        }

        state = .loading
        defer {
            // A tab can disappear while its rates are loading. Let the next appearance retry.
            if Task.isCancelled, currentScope == scope, state == .loading {
                state = .idle
            }
        }
        do {
            let snapshot = try await apiClient.latestExchangeRates(
                currencies: normalized,
                reportingCurrency: reporting,
                refresh: force
            )
            guard !Task.isCancelled, currentScope == scope else { return }
            self.snapshot = snapshot
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, currentScope == scope else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func convert(
        _ amount: Decimal,
        from sourceCurrency: String,
        to reportingCurrency: String
    ) -> Decimal? {
        guard sourceCurrency.caseInsensitiveCompare(reportingCurrency) != .orderedSame else {
            return amount
        }
        return snapshot?.convert(
            amount,
            from: sourceCurrency,
            to: reportingCurrency
        )
    }

    func supports(_ currencies: Set<String>, reportingCurrency: String) -> Bool {
        let normalized = Set(currencies.map { $0.uppercased() })
        if normalized.allSatisfy({ $0 == reportingCurrency.uppercased() }) {
            return true
        }
        return snapshot?.supports(normalized, reportingCurrency: reportingCurrency) == true
    }
}
