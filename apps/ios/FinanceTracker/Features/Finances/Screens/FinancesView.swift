import SwiftUI

struct FinancesView: View {
    var initialMonth = BudgetMonth.start(of: .now)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AppList(usesScrollEdgeFades: false) {
            AppSection {
                NavigationLink {
                    RecurringTransactionsView(allAccounts: true)
                } label: {
                    destination("Recurring", detail: "Bills, subscriptions & regular income", icon: "repeat")
                }
                NavigationLink {
                    DebtsView()
                } label: {
                    destination("Debts", detail: "Money owed to you, by recipient", icon: "user")
                }
                NavigationLink {
                    BudgetOverviewView(initialMonth: initialMonth)
                } label: {
                    destination("Budget", detail: "Spending, pools & category limits", icon: "percentage-circle")
                }
            } footer: {
                Text("Keep track of your plans and commitments in one place.")
            }
        }
        .listStyle(.insetGrouped)
        .financePage()
        .navigationTitle("Finances")
        .navigationBarTitleDisplayMode(.large)
    }

    private func destination(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: AppSpacing.medium) {
            if !dynamicTypeSize.isAccessibilitySize {
                AppIcon(icon, size: 24)
                    .frame(width: 44, height: 48)
                    .background(AppColor.controlFill, in: RoundedRectangle(cornerRadius: AppRadius.medium))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, AppSpacing.small)
    }
}
