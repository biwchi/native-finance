import SwiftUI

/// Keeps category ordering, parent context, and search identical across settings and pickers.
struct CategoryListRows<Row: View>: View {
    let categories: [TransactionCategory]
    let query: String
    var emptyDescription = "Tap + to add one."
    @ViewBuilder let row: (TransactionCategory, Bool) -> Row

    var body: some View {
        let entries = visibleEntries
        ForEach(entries) { entry in
            row(entry.category, entry.isSubcategory)
        }

        if entries.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No categories" : "No categories found",
                iconName: searchText.isEmpty ? "label" : "search",
                description: Text(searchText.isEmpty ? emptyDescription : "Try another name.")
            )
        }
    }

    private var searchText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleEntries: [Entry] {
        let ordered = categories.sorted {
            ($0.sortOrder ?? 1000, $0.name.lowercased(), $0.id.uuidString) <
                ($1.sortOrder ?? 1000, $1.name.lowercased(), $1.id.uuidString)
        }
        let categoryIDs = Set(ordered.map(\.id))
        let roots = ordered.filter { category in
            guard let parentID = category.parentId else { return true }
            return !categoryIDs.contains(parentID)
        }
        return roots.flatMap { parent -> [Entry] in
            let children = ordered.filter { $0.parentId == parent.id }
            let matchingChildren = children.filter {
                searchText.isEmpty || "\(parent.name) › \($0.name)".localizedStandardContains(searchText)
            }
            guard searchText.isEmpty || parent.name.localizedStandardContains(searchText) || !matchingChildren.isEmpty else {
                return []
            }
            return [Entry(category: parent, isSubcategory: false)] +
                matchingChildren.map { Entry(category: $0, isSubcategory: true) }
        }
    }

    private struct Entry: Identifiable {
        let category: TransactionCategory
        let isSubcategory: Bool
        var id: UUID { category.id }
    }
}
