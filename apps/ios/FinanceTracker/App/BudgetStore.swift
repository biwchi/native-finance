import Combine
import Foundation

@MainActor
final class BudgetStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var budget: MonthlyBudget?

    private let apiClient: APIClient
    private var currentScope = ""

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

#if DEBUG
    static func preview(_ budget: MonthlyBudget? = nil) -> BudgetStore {
        let store = BudgetStore()
        store.budget = budget
        if let budget {
            store.currentScope = "\(budget.accountId?.uuidString ?? "all"):\(budget.month)"
        }
        store.state = .loaded
        return store
    }
#endif

    func loadBudget(month: Date, accountID: UUID?, force: Bool = false) async {
        let monthKey = BudgetMonth.key(for: month)
        let scope = "\(accountID?.uuidString ?? "all"):\(monthKey)"
        guard force || scope != currentScope || state != .loaded else { return }

        if scope != currentScope {
            budget = nil
        }
        currentScope = scope
        state = .loading

        do {
            let budget = try await apiClient.monthlyBudget(month: monthKey, accountID: accountID)
            guard !Task.isCancelled, currentScope == scope else { return }
            self.budget = budget
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, currentScope == scope else { return }
            budget = nil
            state = .failed(error.localizedDescription)
        }
    }

    func isLoaded(month: Date, accountID: UUID?) -> Bool {
        state == .loaded && currentScope == "\(accountID?.uuidString ?? "all"):\(BudgetMonth.key(for: month))"
    }

    @discardableResult
    func saveBudget(_ request: MonthlyBudgetRequest) async throws -> MonthlyBudget? {
        let budget = try await apiClient.saveMonthlyBudget(request)
        self.budget = budget
        currentScope = "\(request.accountId?.uuidString ?? "all"):\(request.month)"
        state = .loaded
        return budget
    }
}
