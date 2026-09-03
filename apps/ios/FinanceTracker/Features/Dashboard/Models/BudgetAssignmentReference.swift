import SwiftUI

struct BudgetAssignmentReference: Identifiable {
    var id: UUID { categoryID }
    let categoryID: UUID
    let groupID: UUID?
    let limit: String
}
