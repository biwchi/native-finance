import SwiftUI

#Preview {
    MainView()
        .environmentObject(AccountStore())
        .environmentObject(BudgetStore())
        .environmentObject(ExchangeRateStore())
        .environmentObject(TransactionStore())
}
