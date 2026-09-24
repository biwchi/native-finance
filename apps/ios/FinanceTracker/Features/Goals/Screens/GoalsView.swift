import SwiftUI

struct GoalsView: View {
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @StateObject private var exchangeRateStore = ExchangeRateStore()
    @State private var editor: GoalEditorDestination?
    @State private var selectedGoal: UUID?
    @State private var deletion: SavingsGoal?
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive
    @State private var isAddingAccount = false

    var body: some View {
        AppList(usesScrollEdgeFades: false) {
            AppSection {
                if goalStore.goals.isEmpty {
                    VStack(spacing: AppSpacing.large) {
                        ContentUnavailableView("What are you saving for?", iconName: "target",
                            description: Text(accountStore.accounts.isEmpty
                                              ? "Add an account, then give your goal a name and a target."
                                              : "Give your next goal a name and a target."))
                        PrimaryActionButton(accountStore.accounts.isEmpty ? "Add account" : "Create goal") {
                            if accountStore.accounts.isEmpty { isAddingAccount = true } else { editor = .add }
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(goalStore.goals) { goal in
                        Button {
                            if !editMode.isEditing { selectedGoal = goal.id }
                        } label: {
                            GoalCard(goal: goal, currency: currency(for: goal), progress: progress(for: goal))
                        }
                        .buttonStyle(.plain)
                        .circleSwipeActions(isEnabled: !editMode.isEditing, usesCardLayout: true) {
                            CircleSwipeAction(title: "Delete", icon: "trash") { deletion = goal }
                            CircleSwipeAction(title: "Edit", icon: "edit-pencil", tint: .gray) { editor = .edit(goal) }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        var ids = goalStore.goals.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        do { try goalStore.reorder(ids) } catch { errorMessage = error.localizedDescription }
                    }
                }
            }
        }
        .listRowSpacing(AppSpacing.medium)
        .animateListChanges(value: goalStore.goals.map(\.id))
        .environment(\.editMode, $editMode)
        .financePage()
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                } label: {
                    Label(editMode.isEditing ? "Done reordering goals" : "Reorder goals",
                          icon: editMode.isEditing ? "check" : "reorder")
                }
                .accessibilityLabel(editMode.isEditing ? "Done reordering goals" : "Reorder goals")
                .disabled(goalStore.goals.isEmpty)
                .legacyToolbarIcon()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = .add } label: {
                    Label("Add goal", icon: "plus")
                }
                .disabled(accountStore.accounts.isEmpty)
                .legacyToolbarIcon()
            }
        }
        .navigationDestination(item: $selectedGoal) { id in
            GoalDetailView(goalID: id).legacyNavigationDestination()
        }
        .appSheet(item: $editor) { destination in
            GoalEditorView(goal: destination.goal, initialAccountID: accountStore.selectedAccountID)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .appSheet(isPresented: $isAddingAccount) {
            AccountEditorView().presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .alert("Delete \(deletion?.name ?? "goal")?", isPresented: Binding(
            get: { deletion != nil }, set: { if !$0 { deletion = nil } }
        ), presenting: deletion) { goal in
            Button("Delete goal", role: .destructive) {
                do { try goalStore.delete(goal) } catch { errorMessage = error.localizedDescription }
                deletion = nil
            }
            Button("Cancel", role: .cancel) { deletion = nil }
        } message: { _ in Text("Your account and its money stay as they are.") }
        .alert("Couldn't update goals", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .task(id: currencies.sorted().joined(separator: ",")) {
            await exchangeRateStore.load(currencies: currencies, reportingCurrency: "USD")
        }
        .onChange(of: goalStore.goals.isEmpty) { _, empty in if empty { editMode = .inactive } }
    }

    private var currencies: Set<String> {
        Set(accountStore.accounts.map(\.currency) + transactionStore.allTransactions.map(\.currency))
    }
    private func currency(for goal: SavingsGoal) -> String {
        accountStore.accounts.first { $0.id == goal.accountId }?.currency ?? "USD"
    }
    private func progress(for goal: SavingsGoal) -> GoalProgress? {
        guard accountStore.accounts.contains(where: { $0.id == goal.accountId }),
              let balance = transactionStore.balance(accountID: goal.accountId, currency: currency(for: goal),
                                                      rates: exchangeRateStore.snapshot) else { return nil }
        return GoalProgress(balance: balance, target: goal.target)
    }
}
