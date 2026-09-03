import SwiftUI

struct TransactionsView: View {
    var body: some View {
        TransactionListView()
            .navigationTitle("Transactions")
            .accountSelectorToolbar()
    }
}
