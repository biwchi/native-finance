import Foundation

struct MonthlyBudget: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let accountId: UUID?
    let currency: String
    let monthlyLimit: String?
    let groups: [BudgetGroup]
    let categoryAssignments: [BudgetCategoryAssignment]
    let createdAt: Date
    let updatedAt: Date

    func summaryLimit(useAllocatedBudget: Bool = true) -> Decimal? {
        func amount(_ raw: String?) -> Decimal? {
            guard let raw, let value = Decimal(string: raw), !value.isNaN, value > 0 else { return nil }
            return value
        }

        if let monthlyLimit { return amount(monthlyLimit) }
        guard useAllocatedBudget else { return nil }

        let pools = groups.compactMap { group -> (id: UUID, limit: Decimal)? in
            guard let limit = amount(group.limit) else { return nil }
            return (group.id, limit)
        }
        let poolIDs = Set(pools.map(\.id))
        // A category's own cap is already covered by its pool allocation.
        let categoryLimits = categoryAssignments.compactMap { assignment -> Decimal? in
            if let groupID = assignment.groupId, poolIDs.contains(groupID) { return nil }
            return amount(assignment.limit)
        }
        let total = pools.reduce(Decimal.zero) { $0 + $1.limit } + categoryLimits.reduce(Decimal.zero, +)
        return total > 0 ? total : nil
    }
}
