import Foundation

struct MonthlyBudget: Codable, Identifiable, Equatable {
    let id: UUID
    let accountId: UUID?
    let month: String
    let currency: String
    let monthlyLimit: String?
    let groups: [BudgetGroup]
    let categoryAssignments: [BudgetCategoryAssignment]
    let createdAt: Date
    let updatedAt: Date
}
