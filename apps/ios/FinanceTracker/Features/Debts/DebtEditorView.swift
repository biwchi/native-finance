import SwiftUI

struct DebtEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionStore: TransactionStore
    let debt: Debt?
    let onSave: (Debt) -> Void
    @State private var name: String
    @State private var icon: String
    @State private var color: CategoryColor
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(debt: Debt? = nil, onSave: @escaping (Debt) -> Void) {
        self.debt = debt
        self.onSave = onSave
        _name = State(initialValue: debt?.name ?? "")
        _icon = State(initialValue: debt?.icon ?? "user")
        _color = State(initialValue: debt?.color ?? .blue)
    }

    var body: some View {
        NavigationStack {
            AppForm {
                AppSection {
                    TextField("Name, for example Alexey", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                } footer: {
                    Text("Choose this recipient whenever you lend them money.")
                }
                AppSection("Icon") {
                    CategoryIconPicker(selection: $icon, color: color)
                }
                AppSection("Color") {
                    CategoryColorPicker(selection: $color)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }
            }
            .disabled(isSaving)
            .navigationTitle(debt == nil ? "New debt recipient" : "Edit debt recipient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Group {
                        Button("Cancel") { dismiss() }.disabled(isSaving)
                    }
                    .legacyToolbarControl()
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(debt == nil ? "Create recipient" : "Save changes") {
                    Task { await save() }
                }
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 200)
                .padding()
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: Debt
            if let debt {
                saved = try await transactionStore.updateDebt(debt, name: name, icon: icon, color: color)
            } else {
                saved = try await transactionStore.createDebt(name: name, icon: icon, color: color)
            }
            onSave(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
