import Foundation

struct BudgetCategoryAssignmentRequest: Encodable {
    let categoryId: UUID
    let groupId: UUID?
    let limit: String?
}
