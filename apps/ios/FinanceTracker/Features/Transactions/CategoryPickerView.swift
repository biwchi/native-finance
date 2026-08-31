import SwiftUI

struct CategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionStore: TransactionStore

    @Binding var selection: UUID?
    let kind: TransactionKind

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
                        Label(message, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            Task { await transactionStore.loadCategories(force: true) }
                        }
                        .disabled(transactionStore.isLoadingCategories)
                    }
                }

                ForEach(filteredCategories) { category in
                    Button {
                        select(category.id)
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: category)
                            Text(category.name)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            selectionIndicator(isSelected: selection == category.id)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == category.id ? .isSelected : [])
                }

                if filteredCategories.isEmpty,
                   !transactionStore.isLoadingCategories,
                   transactionStore.categoryErrorMessage == nil {
                    if searchText.isEmpty {
                        ContentUnavailableView(
                            "No categories yet",
                            systemImage: "tag",
                            description: Text("Create a category to organize your transactions.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search categories")
        .task {
            guard !transactionStore.isLoadingCategories else { return }
            await transactionStore.loadCategories()
        }
        .sheet(isPresented: $isPresentingNewCategory, onDismiss: {
            if didCreateCategory {
                dismiss()
            }
        }) {
            NewTransactionCategoryView(kind: kind) { category in
                selection = category.id
                didCreateCategory = true
            }
            .environmentObject(transactionStore)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var categories: [TransactionCategory] {
        transactionStore.categories(for: kind)
    }

    private var searchText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredCategories: [TransactionCategory] {
        guard !searchText.isEmpty else { return categories }
        return categories.filter { $0.name.localizedStandardContains(searchText) }
    }

    private func select(_ categoryID: UUID?) {
        selection = categoryID
        dismiss()
    }

    private func actionIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
    }
}

private struct NewTransactionCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionStore: TransactionStore

    let kind: TransactionKind
    let onCreated: (TransactionCategory) -> Void

    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name", text: $name)
                    LabeledContent("Type", value: kind.title)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
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
            let category = try await transactionStore.createCategory(name: name, kind: kind)
            onCreated(category)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
