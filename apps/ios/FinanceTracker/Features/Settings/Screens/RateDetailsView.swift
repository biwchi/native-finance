import SwiftUI

struct RateDetailsView: View {
    @ObservedObject private var repository = LocalFinanceRepository.shared
    var body: some View {
        AppList {
            if let rates = repository.snapshot.rates {
                AppSection {
                    LabeledContent("Last fetched", value: rates.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("Rates are refreshed automatically once per day when a connection is available.").foregroundStyle(.secondary)
                }
                ForEach(rates.quotes, id: \.currency) { quote in
                    LabeledContent(quote.currency, value: "\(quote.rate) · \(quote.effectiveDate)")
                }
            } else { Text("No exchange rates have been downloaded yet. Original amounts are available in each account’s currency.") }
        }
        .navigationTitle("Exchange rates")
    }
}
