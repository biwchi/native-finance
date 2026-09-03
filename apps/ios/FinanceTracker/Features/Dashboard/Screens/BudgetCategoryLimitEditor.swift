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
        Form {
            Section("Category") {
                Picker("Category", selection: $categoryID) {
                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("Limit") {
                BudgetAmountField(title: "Amount", text: $limit, currency: currency)
            }

            Section("Lives in") {
                Picker("Pool", selection: $groupID) {
                    Text("Standalone").tag(Optional<UUID>.none)
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }
        }
        .navigationTitle("Category limit")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: categoryID) { _, newCategoryID in
            groupID = newCategoryID.flatMap { groupIDByCategory[$0] }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
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
        }
    }
}
