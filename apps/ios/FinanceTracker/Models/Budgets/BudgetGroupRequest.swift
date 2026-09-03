import Foundation

struct BudgetGroupRequest: Encodable {
    let id: UUID
    let name: String
    let limit: String
}
