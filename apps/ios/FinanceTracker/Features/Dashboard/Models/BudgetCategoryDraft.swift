import SwiftUI

struct BudgetCategoryDraft: Identifiable, Equatable {
    var id: UUID { categoryID }
    let categoryID: UUID
    var limit: String = ""
}
