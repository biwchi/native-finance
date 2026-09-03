import SwiftUI

struct CategorySettingsView: View {
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
                    row(category)

                    ForEach(transactionStore.subcategories(of: category)) { subcategory in
                        row(subcategory, isSubcategory: true)
                    }
                }

                if categories.isEmpty,
                   !transactionStore.isLoadingCategories,
                   transactionStore.categoryErrorMessage == nil {
                    ContentUnavailableView(
                        "No categories",
                        iconName: "label",
                        description: Text("Tap + to add one.")
                    )
                }
            }

            if let message = transactionStore.categoryErrorMessage ?? errorMessage {
                Section {
                    Label(message, icon: "warning-triangle")
                        .foregroundStyle(AppColor.destructive)
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editor = CategoryEditor(category: nil, kind: kind)
                } label: {
                    Label("Add category", icon: "plus")
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

    private func row(
        _ category: TransactionCategory,
        isSubcategory: Bool = false
    ) -> some View {
        CategorySettingsRow(
            category: category,
            isSubcategory: isSubcategory,
            onEdit: {
                editor = CategoryEditor(
                    category: category,
                    kind: category.kind
                )
            },
            onDelete: { pendingDeletion = category }
        )
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
