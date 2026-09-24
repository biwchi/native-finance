import SwiftUI

struct CategorySettingsView: View {
    @EnvironmentObject private var transactionStore: TransactionStore

    @State private var kind = TransactionKind.expense
    @State private var editor: CategoryEditor?
    @State private var pendingDeletion: TransactionCategory?
    @State private var errorMessage: String?
    @State private var isDeleting = false
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        AppList(usesCompactTopSpacing: true) {
            AppSection {
                Picker("Type", selection: $kind) {
                    ForEach([TransactionKind.expense, .income]) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, AppSpacing.extraSmall)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            AppSection {
                CategoryListRows(categories: transactionStore.categories(for: kind), query: query) { category, isSubcategory in
                    row(category, isSubcategory: isSubcategory)
                }
            }

            if let message = errorMessage {
                AppSection {
                    Label(message, icon: "warning-triangle")
                        .foregroundStyle(AppColor.destructiveText)
                }
            }
        }
        .listSectionSpacing(.custom(AppSpacing.large))
        .animateListChanges(value: transactionStore.categories.map(\.id))
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            CategorySearchField(query: $query, isFocused: $isSearchFocused)
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.vertical, AppSpacing.medium)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Group {
                    Button {
                        isSearchFocused = false
                        editor = CategoryEditor(category: nil, kind: kind)
                    } label: {
                        Label("Add category", icon: "plus")
                    }
                }
                .legacyToolbarIcon()
            }
        }
        .task {
            await transactionStore.loadCategories()
        }
        .appSheet(item: $editor) { editor in
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

    private func row(
        _ category: TransactionCategory,
        isSubcategory: Bool = false
    ) -> some View {
        CategorySettingsRow(
            category: category,
            isSubcategory: isSubcategory,
            onEdit: {
                isSearchFocused = false
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
