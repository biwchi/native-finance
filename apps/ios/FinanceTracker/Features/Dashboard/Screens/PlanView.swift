import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @StateObject private var budgetRates = ExchangeRateStore()
    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var reportingCurrency = AppPreferences.initialCurrency
    @State private var month = BudgetMonth.start(of: .now)

    var body: some View {
        Group {
            if budgetIsLoaded, budgetStore.budget == nil || convertedBudget != nil {
                BudgetSettingsView(
                    month: month,
                    accountID: accountStore.selectedAccountID,
                    currency: currency,
                    budget: convertedBudget
                )
            } else {
                Form {
                    if case .failed(let message) = budgetStore.state {
                        Section {
                            Text("Couldn’t load budget").font(.headline)
                            Text(message).foregroundStyle(.secondary)
                            Button("Try Again") {
                                Task { await loadBudget(force: true) }
                            }
                        }
                    } else if budgetIsLoaded {
                        Section {
                            FinanceSummaryUnavailable(state: .loaded, rateState: budgetRates.state)
                            Button("Try Again") {
                                Task { await loadRates(force: true) }
                            }
                        }
                    } else {
                        ProgressView("Loading budget")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Budget")
        .task(id: budgetScope) { await loadBudget() }
        .task(id: rateScope) { await loadRates() }
    }

    private var currency: String {
        accountStore.selectedAccount?.currency ?? reportingCurrency.uppercased()
    }

    private var budgetScope: String {
        "\(accountStore.selectedAccountID?.uuidString ?? "all"):\(BudgetMonth.key(for: month))"
    }

    private var budgetIsLoaded: Bool {
        budgetStore.isLoaded(month: month, accountID: accountStore.selectedAccountID)
    }

    private var convertedBudget: MonthlyBudget? {
        guard budgetIsLoaded else { return nil }
        return budgetStore.budget?.converted(to: currency, using: budgetRates)
    }

    private var currencies: Set<String> {
        Set([budgetStore.budget?.currency].compactMap { $0 })
    }

    private var rateScope: String {
        "\(currency):\(currencies.sorted().joined(separator: ","))"
    }

    private func loadBudget(force: Bool = false) async {
        await budgetStore.loadBudget(
            month: month, accountID: accountStore.selectedAccountID, force: force
        )
    }

    private func loadRates(force: Bool = false) async {
        await budgetRates.load(currencies: currencies, reportingCurrency: currency, force: force)
    }
}
