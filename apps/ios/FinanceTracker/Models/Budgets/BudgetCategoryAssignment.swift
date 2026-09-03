import Foundation

struct BudgetCategoryAssignment: Codable, Equatable {
    let categoryId: UUID
    let groupId: UUID?
    let limit: String?
}
