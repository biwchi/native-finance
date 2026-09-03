import Foundation

struct AdaptiveCategoryResolver: CategoryResolving {
    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func resolve(
        description: String,
        kind: TransactionKind,
        categories: [TransactionCategory]
    ) async -> CategoryResolution? {
        let availableCategories = categories.filter { $0.kind == kind }
        guard !availableCategories.isEmpty else { return nil }

        if let history = try? await apiClient.categorySuggestions(
            description: description,
            kind: kind
        ).suggestions.first,
           availableCategories.contains(where: { $0.id == history.categoryId }) {
            return CategoryResolution(
                categoryID: history.categoryId,
                confidence: history.score,
                source: history.source == "exact_history" ? .exactHistory : .fuzzyHistory
            )
        }

        if let local = LocalCategoryMatcher.resolve(
            description: description,
            categories: availableCategories
        ) {
            return local
        }

#if canImport(FoundationModels)
        if CategoryModelGate.isEnabled, #available(iOS 26.0, *) {
            return await FoundationCategoryResolver.resolve(
                description: description,
                categories: availableCategories
            )
        }
#endif

        return nil
    }
}
