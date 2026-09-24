import Combine
import Foundation

@MainActor
final class GoalStore: ObservableObject {
    @Published private(set) var goals: [SavingsGoal] = []
    private let repository: LocalFinanceRepository
    private var subscription: AnyCancellable?

    init(repository: LocalFinanceRepository? = nil) {
        self.repository = repository ?? .shared
        subscription = self.repository.$snapshot.sink { [weak self] in self?.goals = $0.sortedGoals }
    }

    @discardableResult
    func save(id: UUID? = nil, name: String, accountID: UUID, targetAmount: String,
              icon: String, color: CategoryColor, deadline: String?) throws -> SavingsGoal {
        try repository.edit {
            try $0.saveGoal(id: id, name: name, accountID: accountID, targetAmount: targetAmount,
                            icon: icon, color: color, deadline: deadline)
        }
    }

    func reorder(_ ids: [UUID]) throws { try repository.edit { try $0.reorderGoals(ids) } }
    func delete(_ goal: SavingsGoal) throws { try repository.edit { $0.deleteGoal(goal.id) } }
}
