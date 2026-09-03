import SwiftUI

struct BudgetGroupDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var limit: String
    var categories: [BudgetCategoryDraft]

    init(
        id: UUID = UUID(),
        name: String = "",
        limit: String = "",
        categories: [BudgetCategoryDraft] = []
    ) {
        self.id = id
        self.name = name
        self.limit = limit
        self.categories = categories
    }
}
