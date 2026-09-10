import SwiftUI

struct NewTransactionCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionStore: TransactionStore

    let kind: TransactionKind
    let onCreated: (TransactionCategory) -> Void

    @State private var name = ""
    @State private var parentID: UUID?
    @State private var icon = "label"
    @State private var color = CategoryColor.gray
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            AppForm {
                AppSection("Category") {
                    TextField("Name", text: $name)
                    LabeledContent("Type", value: kind.title)

                    Picker("Parent", selection: $parentID) {
                        Text("None").tag(UUID?.none)

                        ForEach(transactionStore.rootCategories(for: kind)) { category in
                            Label {
                                Text(category.name)
                            } icon: {
                                AppIcon(category.displayIcon)
                                    .foregroundStyle(category.displayColor)
                            }
                            .tag(Optional(category.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                AppSection("Icon") {
                    CategoryIconPicker(selection: $icon, color: color)
                }

                AppSection("Color") {
                    CategoryColorPicker(selection: $color)
                }

                if let errorMessage {
                    AppSection {
                        Label(errorMessage, icon: "warning-triangle")
                            .foregroundStyle(AppColor.destructiveText)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Group {
                        Button("Cancel") {
                            dismiss()
                        }
                        .disabled(isSaving)
                    }
                    .legacyToolbarControl()
                }

                ToolbarItem(placement: .confirmationAction) {
                    Group {
                        Button("Add") {
                            Task {
                                await create()
                            }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    }
                    .legacyToolbarControl()
                }
            }
        }
    }

    private func create() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let category = try await transactionStore.createCategory(
                name: name,
                kind: kind,
                parentID: parentID,
                icon: icon,
                color: color
            )
            onCreated(category)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
