import SwiftUI

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            TransactionListView(recentLimit: 4)
                .accountSelectorToolbar()
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AccountStore())
        .environmentObject(TransactionStore())
}
