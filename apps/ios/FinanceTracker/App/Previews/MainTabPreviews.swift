import SwiftUI

#Preview {
    MainTabView()
        .environmentObject(AccountStore())
        .environmentObject(BudgetStore())
        .environmentObject(ExchangeRateStore())
        .environmentObject(TransactionStore())
}
