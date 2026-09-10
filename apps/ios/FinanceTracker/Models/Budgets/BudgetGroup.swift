import Foundation

struct BudgetGroup: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let limit: String
    let sortOrder: Int
}
