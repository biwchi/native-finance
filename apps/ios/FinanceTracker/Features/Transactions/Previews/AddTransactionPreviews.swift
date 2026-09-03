import SwiftUI

#Preview {
    AddTransactionView()
        .environmentObject(AccountStore())
        .environmentObject(TransactionStore())
}
