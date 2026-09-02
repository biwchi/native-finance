import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var defaultCurrency = AppPreferences.initialCurrency

    @AppStorage(AppPreferences.themeKey)
    private var theme = AppTheme.dark.rawValue

    @AppStorage(AppPreferences.preferSimpleTransactionEntryKey)
    private var preferSimpleTransactionEntry = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Preferences") {
                    NavigationLink {
                        CurrencyPickerView(
                            selection: $defaultCurrency,
                            currencyCodes: AppPreferences.currencyCodes
                        )
                        .navigationTitle("Default currency")
                    } label: {
                        LabeledContent {
                            Text(currencyLabel)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Default currency", systemImage: "banknote")
                        }
                    }

                    Picker(selection: $theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.title, systemImage: theme.systemImage)
                                .tag(theme.rawValue)
                        }
                    } label: {
                        Label("Theme", systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Toggle(isOn: $preferSimpleTransactionEntry) {
                        Label("Use quick entry", systemImage: "text.cursor")
                    }
                } header: {
                    Text("Add transactions")
                } footer: {
                    Text("The Add button opens a multiline entry above the keyboard, then shows the transaction form for review.")
                }

                Section {
                    NavigationLink {
                        CategorySettingsView()
                    } label: {
                        Label("Categories", systemImage: "tag")
                    }
                } footer: {
                    Text("Add categories and optional subcategories, change their appearance, or remove custom ones you no longer use.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var currencyLabel: String {
        guard let name = Locale.current.localizedString(forCurrencyCode: defaultCurrency) else {
            return defaultCurrency
        }
        return "\(defaultCurrency) · \(name)"
    }
}

private struct CategorySettingsView: View {
    @EnvironmentObject private var transactionStore: TransactionStore

    @State private var kind = TransactionKind.expense
    @State private var editor: CategoryEditor?
    @State private var pendingDeletion: TransactionCategory?
    @State private var errorMessage: String?
    @State private var isDeleting = false

    var body: some View {
        List {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(TransactionKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(kind == .expense ? "Expense categories" : "Income categories") {
                if transactionStore.isLoadingCategories && categories.isEmpty {
                    ProgressView("Loading categories")
                        .frame(maxWidth: .infinity)
                }

                ForEach(categories) { category in
                    categoryRow(category)

                    ForEach(transactionStore.subcategories(of: category)) { subcategory in
                        categoryRow(subcategory, isSubcategory: true)
                    }
                }

                if categories.isEmpty,
                   !transactionStore.isLoadingCategories,
                   transactionStore.categoryErrorMessage == nil {
                    ContentUnavailableView(
                        "No categories",
                        systemImage: "tag",
                        description: Text("Tap + to add one.")
                    )
                }
            }

            if let message = transactionStore.categoryErrorMessage ?? errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add category", systemImage: "plus") {
                    editor = CategoryEditor(category: nil, kind: kind)
                }
            }
        }
        .task {
            await transactionStore.loadCategories()
        }
        .refreshable {
            await transactionStore.loadCategories(force: true)
        }
        .sheet(item: $editor) { editor in
            CategoryEditorView(editor: editor)
                .environmentObject(transactionStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Delete category?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { category in
            Button("Delete", role: .destructive) {
                Task { await delete(category) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { category in
            Text(deleteMessage(for: category))
        }
        .disabled(isDeleting)
    }

    private var categories: [TransactionCategory] {
        transactionStore.rootCategories(for: kind)
    }

    private func categoryRow(
        _ category: TransactionCategory,
        isSubcategory: Bool = false
    ) -> some View {
        Button {
            editor = CategoryEditor(
                category: category,
                kind: category.kind
            )
        } label: {
            HStack(spacing: 12) {
                if isSubcategory {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                }

                CategoryIcon(category: category)
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !category.isSystem {
                Button("Delete", role: .destructive) {
                    pendingDeletion = category
                }
            }

            Button("Edit") {
                editor = CategoryEditor(
                    category: category,
                    kind: category.kind
                )
            }
            .tint(.blue)
        }
    }

    private func deleteMessage(for category: TransactionCategory) -> String {
        let childCount = transactionStore.subcategories(of: category).count
        if childCount > 0 {
            return "This also deletes \(childCount) subcategor\(childCount == 1 ? "y" : "ies"). Affected transactions will become uncategorized."
        }
        return "Transactions using \"\(category.name)\" will become uncategorized."
    }

    private func delete(_ category: TransactionCategory) async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await transactionStore.deleteCategory(category)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CategoryEditor: Identifiable {
    let category: TransactionCategory?
    let kind: TransactionKind

    var id: String {
        category?.id.uuidString ?? "new-\(kind.rawValue)"
    }
}

private struct CategoryEditorView: View {
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
        _icon = State(initialValue: editor.category?.displayIcon ?? "tag.fill")
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
                                Image(systemName: category.displayIcon)
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
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
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

#Preview {
    SettingsView()
        .environmentObject(TransactionStore())
}
