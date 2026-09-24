import Foundation

extension LocalEditor {
    mutating func saveGoal(id: UUID? = nil, name: String, accountID: UUID, targetAmount: String,
                           icon: String, color: CategoryColor, deadline: String?) throws -> SavingsGoal {
        let existing = id.flatMap { snapshot.goals[$0] }
        guard id == nil || existing != nil else { throw LocalDataError(message: "This goal no longer exists.") }
        _ = try account(accountID)
        if let deadline, GoalDeadline.date(from: deadline, timeZone: TimeZone(secondsFromGMT: 0)!) == nil {
            throw LocalDataError(message: "Choose a valid deadline.")
        }
        let nextOrder = existing?.sortOrder ?? ((snapshot.goals.values.map(\.sortOrder).max() ?? -1) + 1)
        guard nextOrder <= Int(Int32.max) else { throw LocalDataError(message: "Reorder your goals before adding another.") }
        let goal = SavingsGoal(id: id ?? UUID(), name: try self.name(name, limit: 120), accountId: accountID,
                               targetAmount: try amount(targetAmount), icon: try self.name(icon, limit: 80), color: color,
                               deadline: deadline, sortOrder: nextOrder,
                               createdAt: existing?.createdAt ?? now, updatedAt: now)
        try put("goal", key: goal.id.uuidString, goal)
        return goal
    }

    mutating func reorderGoals(_ ids: [UUID]) throws {
        guard ids.count == snapshot.goals.count, Set(ids) == Set(snapshot.goals.keys) else {
            throw LocalDataError(message: "Goal order must contain every goal exactly once.")
        }
        for (index, id) in ids.enumerated() {
            guard var goal = snapshot.goals[id], goal.sortOrder != index else { continue }
            goal.sortOrder = index
            goal.updatedAt = now
            try put("goal", key: id.uuidString, goal)
        }
    }

    mutating func deleteGoal(_ id: UUID) { erase("goal", key: id.uuidString) }
}
