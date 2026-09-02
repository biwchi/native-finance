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

#if DEBUG
    static func preview(transactions: [FinanceTransaction]) -> TransactionStore {
        let store = TransactionStore()
        store.transactions = transactions
        store.categories = Array(Set(transactions.compactMap(\.category)))
        store.hasLoadedCategories = true
        store.state = .loaded
        return store
    }
#endif

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

    func rootCategories(for kind: TransactionKind) -> [TransactionCategory] {
        categories(for: kind).filter { $0.parentId == nil }
    }

    func subcategories(of category: TransactionCategory) -> [TransactionCategory] {
        categories(for: category.kind).filter { $0.parentId == category.id }
    }

    func categoryPath(_ category: TransactionCategory) -> String {
        guard let parentID = category.parentId,
              let parent = categories.first(where: { $0.id == parentID }) else {
            return category.name
        }
        return "\(parent.name) › \(category.name)"
    }

    @discardableResult
    func createCategory(
        name: String,
        kind: TransactionKind,
        parentID: UUID? = nil,
        icon: String = "tag.fill",
        color: CategoryColor = .gray
    ) async throws -> TransactionCategory {
        let category = try await apiClient.createCategory(
            CreateCategoryRequest(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind,
                parentId: parentID,
                icon: icon,
                color: color
            )
        )

        categories.append(category)
        hasLoadedCategories = true
        return category
    }

    @discardableResult
    func updateCategory(
        _ existingCategory: TransactionCategory,
        name: String,
        parentID: UUID?,
        icon: String,
        color: CategoryColor
    ) async throws -> TransactionCategory {
        let category = try await apiClient.updateCategory(
            id: existingCategory.id,
            with: UpdateCategoryRequest(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                parentId: parentID,
                icon: icon,
                color: color
            )
        )

        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        }
        transactions = transactions.map { transaction in
            guard transaction.category?.id == category.id else { return transaction }
            return transaction.replacingCategory(with: category)
        }
        return category
    }

    func deleteCategory(_ category: TransactionCategory) async throws {
        let removedIDs = Set(
            [category.id] + categories
                .filter { $0.parentId == category.id }
                .map(\.id)
        )
        _ = try await apiClient.deleteCategory(id: category.id)
        categories.removeAll { removedIDs.contains($0.id) }
        transactions = transactions.map { transaction in
            guard let categoryID = transaction.category?.id,
                  removedIDs.contains(categoryID) else { return transaction }
            return transaction.replacingCategory(with: nil)
        }
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
        _ request: TransactionRequest
    ) async throws -> FinanceTransaction {
        let transaction = try await apiClient.createTransaction(request)
        if request.recurrence != nil {
            await loadTransactions(accountID: currentAccountID)
        } else {
            apply(transaction)
        }
        return transaction
    }

    @discardableResult
    func createTransfer(_ request: TransferRequest) async throws -> TransferResponse {
        let transfer = try await apiClient.createTransfer(request)
        apply(transfer.source)
        apply(transfer.destination)
        return transfer
    }

    @discardableResult
    func updateTransaction(id: UUID, with request: TransactionRequest) async throws -> FinanceTransaction {
        let wasRecurring = transactions.first { $0.id == id }?.recurrence != nil
        let transaction = try await apiClient.updateTransaction(id: id, with: request)
        if wasRecurring || request.recurrence != nil {
            await loadTransactions(accountID: currentAccountID)
        } else {
            apply(transaction)
        }
        return transaction
    }

    func deleteTransaction(_ transaction: FinanceTransaction) async throws {
        _ = try await apiClient.deleteTransaction(id: transaction.id)
        transactions.removeAll { $0.id == transaction.id }
        state = .loaded
    }

    private func apply(_ transaction: FinanceTransaction) {
        transactions.removeAll { $0.id == transaction.id }

        if currentAccountID == nil || currentAccountID == transaction.accountId {
            transactions.append(transaction)
            transactions.sort {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.createdAt > $1.createdAt
            }
        }
        state = .loaded
    }
}

private extension FinanceTransaction {
    func replacingCategory(with category: TransactionCategory?) -> FinanceTransaction {
        FinanceTransaction(
            id: id,
            accountId: accountId,
            kind: kind,
            amount: amount,
            currency: currency,
            category: category,
            merchant: merchant,
            payee: payee,
            note: note,
            occurredAt: occurredAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            recurrence: recurrence
        )
    }
}
