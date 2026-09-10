import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @AppStorage(AppPreferences.defaultCurrencyKey) private var reportingCurrency = AppPreferences.initialCurrency
    var body: some View {
        let budget = budgetStore.budget(accountID: accountStore.selectedAccountID)
        BudgetSettingsView(
            accountID: accountStore.selectedAccountID,
            currency: budget?.currency ?? accountStore.selectedAccount?.currency ?? reportingCurrency.uppercased(),
            budget: budget
        )
        .navigationTitle("Budget")
    }
}
