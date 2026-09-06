import SwiftUI

struct DebtRecipientsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionStore: TransactionStore
    @State private var editingDebt: Debt?
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            List {
                if let message = transactionStore.debtErrorMessage {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try again") { Task { await transactionStore.loadDebts() } }
                }
                if transactionStore.isLoadingDebts {
                    ProgressView("Loading recipients")
                } else if transactionStore.debts.isEmpty && transactionStore.debtErrorMessage == nil {
                    ContentUnavailableView("No recipients", iconName: "user",
                        description: Text("Create a recipient to start lending money."))
                }
                ForEach(transactionStore.debts) { debt in
                    Button { editingDebt = debt } label: {
                        HStack {
                            DebtIcon(debt: debt)
                            Text(debt.name).foregroundStyle(.primary)
                            Spacer()
                            AppIcon("nav-arrow-right", size: 16).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("Edit recipient name, icon, and color")
                }
            }
            .navigationTitle("Debt recipients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreating = true } label: { Label("New recipient", icon: "plus") }
                }
            }
            .task { await transactionStore.loadDebts() }
            .refreshable { await transactionStore.loadDebts() }
            .sheet(item: $editingDebt) { debt in DebtEditorView(debt: debt) { _ in } }
            .sheet(isPresented: $isCreating) { DebtEditorView { _ in } }
        }
    }
}
