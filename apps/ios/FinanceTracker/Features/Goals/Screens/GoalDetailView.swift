import SwiftUI

struct GoalDetailView: View {
    let goalID: UUID
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @StateObject private var exchangeRateStore = ExchangeRateStore()
    @State private var isEditing = false
    @State private var isAddingMoney = false
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false

    var body: some View {
        AppList(usesScrollEdgeFades: false) {
            if let goal, let account {
                AppSection {
                    GoalCard(goal: goal, currency: account.currency, progress: progress)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                AppSection("Linked account") {
                    HStack(spacing: AppSpacing.medium) {
                        AccountIconBadge(iconName: account.icon, color: account.iconColor.color)
                        VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                            Text(account.name).font(.headline)
                            if let progress {
                                Text(MoneyFormatter.format(progress.balance, currency: account.currency, roundToWhole: roundTotals))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else { Text("Balance unavailable").font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                }
                AppSection {
                    PrimaryActionButton("Top up account") { isAddingMoney = true }
                        .listRowBackground(Color.clear)
                }
            }
        }
        .financePage()
        .navigationTitle(goal?.name ?? "Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }.legacyToolbarControl().disabled(goal == nil)
            }
        }
        .appSheet(isPresented: $isEditing) {
            if let goal { GoalEditorView(goal: goal).presentationDetents([.large]).presentationDragIndicator(.visible) }
        }
        .appSheet(isPresented: $isAddingMoney) {
            if let account {
                AddTransactionView(initialAccountID: account.id, initialKind: .income)
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
        }
        .task(id: currencies.sorted().joined(separator: ",")) {
            await exchangeRateStore.load(currencies: currencies, reportingCurrency: account?.currency ?? "USD")
        }
        .onChange(of: goal == nil) { _, missing in if missing { dismiss() } }
    }
    private var goal: SavingsGoal? { goalStore.goals.first { $0.id == goalID } }
    private var account: Account? { accountStore.accounts.first { $0.id == goal?.accountId } }
    private var currencies: Set<String> {
        Set(transactionStore.allTransactions.filter { $0.accountId == goal?.accountId }.map(\.currency) + [account?.currency ?? "USD"])
    }
    private var progress: GoalProgress? {
        guard let goal, let account,
              let balance = transactionStore.balance(accountID: account.id, currency: account.currency, rates: exchangeRateStore.snapshot) else { return nil }
        return GoalProgress(balance: balance, target: goal.target)
    }
}
