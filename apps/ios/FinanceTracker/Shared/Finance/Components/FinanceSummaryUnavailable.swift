import SwiftUI

struct FinanceSummaryUnavailable: View {
    let state: TransactionStore.State
    let rateState: ExchangeRateStore.State
    var body: some View {
        VStack(spacing: 6) {
            Text("Combined total unavailable").font(.subheadline)
            Text("An exchange rate is missing. Transactions are shown in their original currencies.")
                .font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
