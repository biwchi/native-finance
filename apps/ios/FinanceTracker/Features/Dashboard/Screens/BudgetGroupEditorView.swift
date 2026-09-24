import SwiftUI

struct BudgetGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var group: BudgetGroupDraft
    let isNew: Bool
    let categories: [TransactionCategory]
    let currency: String
    let unavailableCategoryIDs: Set<UUID>
    let onSave: (BudgetGroupDraft) -> Void

    @State private var searchText = ""
    @State private var didRequestInitialFocus = false
    @FocusState private var isNameFocused: Bool
    @FocusState private var isSearchFocused: Bool

    init(
        group: BudgetGroupDraft,
        isNew: Bool = false,
        categories: [TransactionCategory],
        currency: String,
        unavailableCategoryIDs: Set<UUID>,
        onSave: @escaping (BudgetGroupDraft) -> Void
    ) {
        _group = State(initialValue: group)
        self.isNew = isNew
        self.categories = categories
        self.currency = currency
        self.unavailableCategoryIDs = unavailableCategoryIDs
        self.onSave = onSave
    }

    var body: some View {
        AppList {
            AppSection("Pool details") {
                TextField("Name", text: $group.name)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { isNameFocused = false }
                    .accessibilityIdentifier("poolNameField")
                BudgetAmountField(title: "Limit", text: $group.limit, currency: currency)
            }

            AppSection("Categories") {
                CategoryListRows(
                    categories: categories,
                    query: searchText,
                    emptyDescription: "Add expense categories in Settings."
                ) { category, isSubcategory in
                    categoryRow(category, isSubcategory: isSubcategory)
                }
            }
        }
        .navigationTitle(isNew ? "New pool" : "Edit pool")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            CategorySearchField(query: $searchText, isFocused: $isSearchFocused)
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.vertical, AppSpacing.medium)
        }
        .task {
            guard isNew, !didRequestInitialFocus else { return }
            // Wait for the navigation transition so the field can become first responder.
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            didRequestInitialFocus = true
            isNameFocused = true
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Group {
                    Button("Done") {
                        onSave(group)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
                .legacyToolbarControl()
            }
        }
    }

    private func categoryRow(_ category: TransactionCategory, isSubcategory: Bool) -> some View {
        let isUnavailable = unavailableCategoryIDs.contains(category.id)
        let isSelected = group.categories.contains { $0.categoryID == category.id }

        return Button {
            guard !isUnavailable else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if isSelected {
                    group.categories.removeAll { $0.categoryID == category.id }
                } else {
                    group.categories.append(BudgetCategoryDraft(categoryID: category.id))
                }
            }
        } label: {
            CategoryListRow(
                category: category,
                isSubcategory: isSubcategory,
                subtitle: isUnavailable ? "Already assigned elsewhere" : nil,
                accessory: .checkmark(isSelected: isSelected)
            )
            .opacity(isUnavailable ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var canSave: Bool {
        !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            BudgetAmountParser.parse(group.limit) != nil
    }
}
