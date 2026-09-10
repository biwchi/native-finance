import Foundation

struct BudgetCategoryAssignment: Codable, Equatable, Sendable {
    let categoryId: UUID
    let groupId: UUID?
    let limit: String?
}
