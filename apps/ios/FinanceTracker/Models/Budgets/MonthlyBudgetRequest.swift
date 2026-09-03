import Foundation

struct MonthlyBudgetRequest: Encodable {
    let month: String
    let accountId: UUID?
    let currency: String
    let monthlyLimit: String?
    let groups: [BudgetGroupRequest]
    let categoryAssignments: [BudgetCategoryAssignmentRequest]
}
