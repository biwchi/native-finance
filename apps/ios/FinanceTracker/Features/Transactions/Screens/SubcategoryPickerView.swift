import SwiftUI

struct SubcategoryPickerView: View {
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
