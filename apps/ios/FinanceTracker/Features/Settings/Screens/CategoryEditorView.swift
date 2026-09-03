import SwiftUI

struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionStore: TransactionStore

    let editor: CategoryEditor

    @State private var name: String
    @State private var kind: TransactionKind
    @State private var parentID: UUID?
    @State private var icon: String
    @State private var color: CategoryColor
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(editor: CategoryEditor) {
        self.editor = editor
        _name = State(initialValue: editor.category?.name ?? "")
        _kind = State(initialValue: editor.kind)
        _parentID = State(initialValue: editor.category?.parentId)
        _icon = State(initialValue: editor.category?.displayIcon ?? "label")
        _color = State(initialValue: editor.category?.displayCategoryColor ?? .gray)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name", text: $name)

                    if editor.category == nil {
                        Picker("Type", selection: $kind) {
                            ForEach(TransactionKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        LabeledContent("Type", value: kind.title)
                    }

                    Picker("Parent", selection: $parentID) {
                        Text("None").tag(UUID?.none)

                        ForEach(parentCandidates) { category in
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
                    .disabled(hasSubcategories)

                    if hasSubcategories {
                        Text("Move or delete its subcategories before assigning a parent.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Icon") {
                    CategoryIconPicker(selection: $icon, color: color)
                }

                Section("Color") {
                    CategoryColorPicker(selection: $color)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, icon: "warning-triangle")
                            .foregroundStyle(AppColor.destructive)
                    }
                }
            }
            .navigationTitle(editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .onChange(of: kind) {
                parentID = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var editorTitle: String {
        if editor.category != nil { return "Edit category" }
        return "New category"
    }

    private var parentCandidates: [TransactionCategory] {
        transactionStore.rootCategories(for: kind).filter {
            $0.id != editor.category?.id
        }
    }

    private var hasSubcategories: Bool {
        guard let category = editor.category else { return false }
        return !transactionStore.subcategories(of: category).isEmpty
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && hasChanges
    }

    private var hasChanges: Bool {
        guard let category = editor.category else { return true }
        return trimmedName != category.name ||
            parentID != category.parentId ||
            icon != category.displayIcon ||
            color != category.displayCategoryColor
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let category = editor.category {
                try await transactionStore.updateCategory(
                    category,
                    name: trimmedName,
                    parentID: parentID,
                    icon: icon,
                    color: color
                )
            } else {
                try await transactionStore.createCategory(
                    name: trimmedName,
                    kind: kind,
                    parentID: parentID,
                    icon: icon,
                    color: color
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
