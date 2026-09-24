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
        AppList {
            AppSection {
                Button {
                    select(nil)
                } label: {
                    HStack(spacing: AppSpacing.medium) {
                        actionIcon("nosign", color: .secondary)
                        Text("No category")
                            .foregroundStyle(.primary)
                        Spacer()
                        AccentSelectionButton.Indicator(isSelected: selection == nil)
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

            AppSection {
                CategoryListRows(
                    categories: transactionStore.categories(for: kind),
                    query: query,
                    emptyDescription: "Create a category to organize your transactions."
                ) { category, isSubcategory in
                    Button {
                        select(category.id)
                    } label: {
                        CategoryListRow(
                            category: category,
                            isSubcategory: isSubcategory,
                            accessory: .checkmark(isSelected: selection == category.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selection == category.id ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selection == category.id ? .isSelected : [])
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search categories")
        .task {
            guard !transactionStore.isLoadingCategories else { return }
            await transactionStore.loadCategories()
        }
        .appSheet(isPresented: $isPresentingNewCategory, onDismiss: {
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
}
