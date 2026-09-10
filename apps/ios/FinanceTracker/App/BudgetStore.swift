import Combine
import Foundation

@MainActor
final class BudgetStore: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var state: State = .loaded
    @Published private(set) var budget: MonthlyBudget?
    @Published private(set) var budgets: [String: MonthlyBudget] = [:]
    private let repository: LocalFinanceRepository
    private var currentScope = "all"
    private var subscription: AnyCancellable?

    init(apiClient: APIClient = APIClient(), repository: LocalFinanceRepository? = nil) {
        self.repository = repository ?? .shared
        subscription = self.repository.$snapshot.sink { [weak self] snapshot in
            guard let self else { return }
            self.budgets = snapshot.budgets
            self.budget = snapshot.budgets[self.currentScope]
        }
    }

    func loadBudget(accountID: UUID?, force: Bool = false) async {
        currentScope = budgetKey(accountID: accountID)
        budget = repository.snapshot.budgets[currentScope]
        state = .loaded
    }

    func budget(accountID: UUID?) -> MonthlyBudget? { budgets[budgetKey(accountID: accountID)] }
    func isLoaded(accountID: UUID?) -> Bool { true }

    @discardableResult
    func saveBudget(_ request: MonthlyBudgetRequest) async throws -> MonthlyBudget? {
        let saved = try repository.edit { try $0.saveBudget(request) }
        currentScope = budgetKey(accountID: request.accountId)
        budget = saved
        state = .loaded
        return saved
    }
#if DEBUG
    static func preview(_ budget: MonthlyBudget? = nil) -> BudgetStore {
        let store = BudgetStore()
        store.subscription = nil
        store.budget = budget
        if let budget {
            store.currentScope = budgetKey(accountID: budget.accountId)
            store.budgets[store.currentScope] = budget
        }
        return store
    }
#endif
}
