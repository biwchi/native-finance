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
                    HStack(spacing: AppSpacing.medium) {
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
                    HStack(spacing: AppSpacing.medium) {
                        actionIcon("plus", color: AppColor.accent)
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
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
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
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.small))
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
