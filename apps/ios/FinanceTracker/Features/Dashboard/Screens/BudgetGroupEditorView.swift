import SwiftUI

struct BudgetGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var group: BudgetGroupDraft
    let categories: [TransactionCategory]
    let currency: String
    let unavailableCategoryIDs: Set<UUID>
    let onSave: (BudgetGroupDraft) -> Void

    @State private var searchText = ""

    init(
        group: BudgetGroupDraft,
        categories: [TransactionCategory],
        currency: String,
        unavailableCategoryIDs: Set<UUID>,
        onSave: @escaping (BudgetGroupDraft) -> Void
    ) {
        _group = State(initialValue: group)
        self.categories = categories
        self.currency = currency
        self.unavailableCategoryIDs = unavailableCategoryIDs
        self.onSave = onSave
    }

    var body: some View {
        List {
            Section("Pool details") {
                TextField("Name", text: $group.name)
                BudgetAmountField(title: "Limit", text: $group.limit, currency: currency)
            }

            Section("Categories") {
                ForEach(filteredCategories) { category in
                    let isUnavailable = unavailableCategoryIDs.contains(category.id)
                    let isSelected = group.categories.contains { $0.categoryID == category.id }

                    Button {
                        guard !isUnavailable else { return }
                        if isSelected {
                            group.categories.removeAll { $0.categoryID == category.id }
                        } else {
                            group.categories.append(BudgetCategoryDraft(categoryID: category.id))
                        }
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: category, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name).foregroundStyle(.primary)
                                if isUnavailable {
                                    Text("Already assigned elsewhere")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            AppIcon(isSelected ? "check-circle" : "circle")
                                .foregroundStyle(isSelected ? AppColor.accent : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isUnavailable)
                }
            }
        }
        .navigationTitle(group.name.isEmpty ? "New pool" : group.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Find a category")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onSave(group)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }

    private var filteredCategories: [TransactionCategory] {
        guard !searchText.isEmpty else { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var canSave: Bool {
        !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            BudgetAmountParser.parse(group.limit) != nil
    }
}
