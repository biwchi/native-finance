import Foundation

struct ExchangeRateSnapshot: Codable, Equatable {
    let baseCurrency: String
    let reportingCurrency: String
    let quotes: [ExchangeRateQuote]
    let fetchedAt: Date
    let stale: Bool

    func convert(
        _ amount: Decimal,
        from sourceCurrency: String,
        to targetCurrency: String
    ) -> Decimal? {
        let source = sourceCurrency.uppercased()
        let target = targetCurrency.uppercased()
        guard source != target else { return amount }
        guard let sourceRate = rate(for: source),
              let targetRate = rate(for: target),
              sourceRate > 0 else {
            return nil
        }
        return amount / sourceRate * targetRate
    }

    func supports(_ currencies: Set<String>, reportingCurrency: String) -> Bool {
        currencies.allSatisfy { currency in
            currency.uppercased() == reportingCurrency.uppercased() || rate(for: currency) != nil
        } && rate(for: reportingCurrency) != nil
    }

    private func rate(for currency: String) -> Decimal? {
        guard let value = quotes.first(where: {
            $0.currency.caseInsensitiveCompare(currency) == .orderedSame
        })?.rate else {
            return nil
        }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
}
