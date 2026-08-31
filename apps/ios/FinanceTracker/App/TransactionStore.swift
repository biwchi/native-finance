import Combine
import Foundation

@MainActor
final class TransactionStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transactions: [FinanceTransaction] = []
    @Published private(set) var categories: [TransactionCategory] = []
    @Published private(set) var isLoadingCategories = false
    @Published private(set) var categoryErrorMessage: String?

    private let apiClient: APIClient
    private var currentAccountID: UUID?
    private var hasLoadedCategories = false

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func loadTransactions(accountID: UUID?) async {
        currentAccountID = accountID
        state = .loading

        do {
            let transactions = try await apiClient.transactions(accountID: accountID)
            guard !Task.isCancelled, currentAccountID == accountID else { return }

            self.transactions = transactions
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, currentAccountID == accountID else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadCategories(force: Bool = false) async {
        guard force || !hasLoadedCategories else { return }

        isLoadingCategories = true
        categoryErrorMessage = nil
        defer { isLoadingCategories = false }

        do {
            categories = try await apiClient.categories()
            hasLoadedCategories = true
        } catch {
            hasLoadedCategories = false
            categoryErrorMessage = error.localizedDescription
        }
    }

    func categories(for kind: TransactionKind) -> [TransactionCategory] {
        categories
            .filter { $0.kind == kind }
            .sorted {
                let leftOrder = $0.sortOrder ?? 1_000
                let rightOrder = $1.sortOrder ?? 1_000
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    @discardableResult
    func createCategory(name: String, kind: TransactionKind) async throws -> TransactionCategory {
        let category = try await apiClient.createCategory(
            CreateCategoryRequest(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind
            )
        )

        categories.append(category)
        hasLoadedCategories = true
        return category
    }

    func categorySuggestions(
        description: String,
        kind: TransactionKind
    ) async throws -> [CategorySuggestion] {
        try await apiClient
            .categorySuggestions(description: description, kind: kind)
            .suggestions
    }

    @discardableResult
    func createTransaction(
        _ request: CreateTransactionRequest
    ) async throws -> FinanceTransaction {
        let transaction = try await apiClient.createTransaction(request)

        if currentAccountID == nil || currentAccountID == transaction.accountId {
            transactions.append(transaction)
            transactions.sort {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.createdAt > $1.createdAt
            }
            state = .loaded
        }

        return transaction
    }
}
