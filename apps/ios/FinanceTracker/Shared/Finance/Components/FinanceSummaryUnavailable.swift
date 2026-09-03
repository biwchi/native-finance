import SwiftUI

struct FinanceSummaryUnavailable: View {
    let state: TransactionStore.State
    let rateState: ExchangeRateStore.State

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView("Loading summary")
            case .failed:
                Label("Summary unavailable", icon: "wifi-warning")
            case .loaded:
                switch rateState {
                case .idle, .loading: ProgressView("Converting amounts")
                case .failed: Label("Couldn’t convert currencies", icon: "wifi-warning")
                case .loaded: Label("Some amounts could not be converted", icon: "warning-triangle")
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
