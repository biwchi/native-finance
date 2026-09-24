import SwiftUI

struct BudgetCategoryLimitEditor: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [TransactionCategory]
    let groups: [BudgetGroupDraft]
    let currency: String
    let groupIDByCategory: [UUID: UUID]
    let onSave: (BudgetCategoryDraft, UUID?) -> Void

    @State private var categoryID: UUID?
    @State private var groupID: UUID?
    @State private var limit: String

    init(
        assignment: BudgetAssignmentReference?,
        categories: [TransactionCategory],
        groups: [BudgetGroupDraft],
        currency: String,
        groupIDByCategory: [UUID: UUID],
        onSave: @escaping (BudgetCategoryDraft, UUID?) -> Void
    ) {
        self.categories = categories
        self.groups = groups
        self.currency = currency
        self.groupIDByCategory = groupIDByCategory
        self.onSave = onSave
        let initialCategoryID = assignment?.categoryID ?? categories.first?.id
        _categoryID = State(initialValue: initialCategoryID)
        _groupID = State(
            initialValue: assignment?.groupID ?? initialCategoryID.flatMap { groupIDByCategory[$0] }
        )
        _limit = State(initialValue: assignment?.limit ?? "")
    }

    var body: some View {
        AppForm {
            AppSection("Category") {
                AppNavigationLink {
                    BudgetLimitCategoryPicker(categories: categories, selection: $categoryID)
                } label: {
                    LabeledContent(
                        "Category",
                        value: categories.first { $0.id == categoryID }?.name ?? "Select category"
                    )
                }
            }

            AppSection("Limit") {
                BudgetAmountField(title: "Amount", text: $limit, currency: currency)
            }

            AppSection("Lives in") {
                Picker("Pool", selection: $groupID) {
                    Text("Standalone").tag(Optional<UUID>.none)
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .navigationTitle("Category limit")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: categoryID) { _, newCategoryID in
            groupID = newCategoryID.flatMap { groupIDByCategory[$0] }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Group {
                    Button("Done") {
                        guard let categoryID else { return }
                        onSave(
                            BudgetCategoryDraft(categoryID: categoryID, limit: limit),
                            groupID
                        )
                        dismiss()
                    }
                    .disabled(categoryID == nil || BudgetAmountParser.parse(limit) == nil)
                }
                .legacyToolbarControl()
            }
        }
    }
}

private struct BudgetLimitCategoryPicker: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [TransactionCategory]
    @Binding var selection: UUID?

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        AppList {
            AppSection {
                CategoryListRows(
                    categories: categories,
                    query: query,
                    emptyDescription: "Add expense categories in Settings."
                ) { category, isSubcategory in
                    Button {
                        isSearchFocused = false
                        selection = category.id
                        dismiss()
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
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            CategorySearchField(query: $query, isFocused: $isSearchFocused)
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.vertical, AppSpacing.medium)
        }
    }
}
