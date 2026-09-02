import SwiftUI

struct CategoryPickerView: View {
    @EnvironmentObject private var transactionStore: TransactionStore

    @Binding var selection: UUID?
    let kind: TransactionKind
    let onSelect: (UUID?) -> Void

    @State private var query = ""
    @State private var isPresentingNewCategory = false
    @State private var didCreateCategory = false

    var body: some View {
        List {
            Section {
                Button {
                    select(nil)
                } label: {
                    HStack(spacing: 12) {
                        actionIcon("nosign", color: .secondary)
                        Text("No category")
                            .foregroundStyle(.primary)
                        Spacer()
                        selectionIndicator(isSelected: selection == nil)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == nil ? .isSelected : [])

                Button {
                    isPresentingNewCategory = true
                } label: {
                    HStack(spacing: 12) {
                        actionIcon("plus", color: .accentColor)
                        Text("New category")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            Section(kind == .expense ? "Expense categories" : "Income categories") {
                if transactionStore.isLoadingCategories && categories.isEmpty {
                    ProgressView("Loading categories")
                        .frame(maxWidth: .infinity)
                } else if let message = transactionStore.categoryErrorMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(message, icon: "wifi-warning")
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            Task { await transactionStore.loadCategories(force: true) }
                        }
                        .disabled(transactionStore.isLoadingCategories)
                    }
                }

                ForEach(filteredCategories) { category in
                    let children = transactionStore.subcategories(of: category)

                    if searchText.isEmpty && !children.isEmpty {
                        NavigationLink(value: category) {
                            CategorySelectionRow(
                                category: category,
                                title: category.name,
                                isSelected: selection == category.id ||
                                    children.contains(where: { $0.id == selection })
                            )
                        }
                    } else {
                        Button {
                            select(category.id)
                        } label: {
                            CategorySelectionRow(
                                category: category,
                                title: transactionStore.categoryPath(category),
                                isSelected: selection == category.id
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == category.id ? .isSelected : [])
                    }
                }

                if filteredCategories.isEmpty,
                   !transactionStore.isLoadingCategories,
                   transactionStore.categoryErrorMessage == nil {
                    if searchText.isEmpty {
                        ContentUnavailableView(
                            "No categories yet",
                            iconName: "label",
                            description: Text("Create a category to organize your transactions.")
                        )
                    } else {
                        ContentUnavailableView(
                            "No categories found",
                            iconName: "search",
                            description: Text("No results for “\(searchText)”.")
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search categories")
        .navigationDestination(for: TransactionCategory.self) { parent in
            SubcategoryPickerView(
                parent: parent,
                subcategories: transactionStore.subcategories(of: parent),
                selection: selection,
                onSelect: select
            )
        }
        .task {
            guard !transactionStore.isLoadingCategories else { return }
            await transactionStore.loadCategories()
        }
        .sheet(isPresented: $isPresentingNewCategory, onDismiss: {
            if didCreateCategory {
                onSelect(selection)
            }
        }) {
            NewTransactionCategoryView(kind: kind) { category in
                selection = category.id
                didCreateCategory = true
            }
            .environmentObject(transactionStore)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var categories: [TransactionCategory] {
        transactionStore.rootCategories(for: kind)
    }

    private var searchText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredCategories: [TransactionCategory] {
        guard !searchText.isEmpty else { return categories }
        return transactionStore.categories(for: kind).filter {
            transactionStore.categoryPath($0).localizedStandardContains(searchText)
        }
    }

    private func select(_ categoryID: UUID?) {
        selection = categoryID
        onSelect(categoryID)
    }

    private func actionIcon(_ name: String, color: Color) -> some View {
        AppIcon(name, size: 16)
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        if isSelected {
            AppIcon("check", size: 17)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
    }
}

private struct SubcategoryPickerView: View {
    let parent: TransactionCategory
    let subcategories: [TransactionCategory]
    let selection: UUID?
    let onSelect: (UUID?) -> Void

    var body: some View {
        List {
            Section {
                Button {
                    onSelect(parent.id)
                } label: {
                    CategorySelectionRow(
                        category: parent,
                        title: "Use \(parent.name)",
                        isSelected: selection == parent.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == parent.id ? .isSelected : [])
            } footer: {
                Text("A subcategory is optional.")
            }

            Section("Subcategories") {
                ForEach(subcategories) { category in
                    Button {
                        onSelect(category.id)
                    } label: {
                        CategorySelectionRow(
                            category: category,
                            title: category.name,
                            isSelected: selection == category.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == category.id ? .isSelected : [])
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(parent.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CategorySelectionRow: View {
    let category: TransactionCategory
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category)
            Text(title)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if isSelected {
                AppIcon("check", size: 17)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct NewTransactionCategoryView: View {
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
            Form {
                Section("Category") {
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

                Section("Icon") {
                    CategoryIconPicker(selection: $icon, color: color)
                }

                Section("Color") {
                    CategoryColorPicker(selection: $color)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, icon: "warning-triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await create()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
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
