import SwiftUI

struct DebtRecipientPicker: View {
    @EnvironmentObject private var transactionStore: TransactionStore
    @Binding var selection: UUID?
    @State private var isCreating = false
    @State private var editingDebt: Debt?

    var body: some View {
        HStack {
            Menu {
                Picker("Recipient", selection: $selection) {
                    Text("Choose recipient").tag(UUID?.none)
                    ForEach(transactionStore.debts) { debt in
                        Label(debt.name, icon: debt.icon ?? "user").tag(Optional(debt.id))
                    }
                }
                Button { isCreating = true } label: { Label("New recipient", icon: "plus") }
                if let selectedDebt {
                    Button("Edit recipient") { editingDebt = selectedDebt }
                }

            } label: {
                HStack {
                    if let selectedDebt { DebtIcon(debt: selectedDebt, size: 32) }
                    Text(selectedName).foregroundStyle(.primary)
                    AppIcon("nav-arrow-down", size: 14).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("Debt recipient: \(selectedName)")
        }
        .sheet(item: $editingDebt) { debt in
            DebtEditorView(debt: debt) { _ in }
        }
        .sheet(isPresented: $isCreating) {
            DebtEditorView { debt in selection = debt.id }
        }
    }

    private var selectedDebt: Debt? {
        transactionStore.debts.first { $0.id == selection }
    }

    private var selectedName: String {
        transactionStore.debts.first { $0.id == selection }?.name
            ?? "Choose recipient"
    }
}
