import Foundation

struct TransactionCategory: Codable, Identifiable, Hashable {
    let id: UUID
    let systemKey: String?
    let name: String
    let kind: TransactionKind
    let isSystem: Bool
    let examples: [String]?
    let sortOrder: Int?
    let createdAt: Date?
    let updatedAt: Date?

    var classificationExamples: [String] {
        [name] + (examples ?? [])
    }
}

struct CreateCategoryRequest: Encodable {
    let name: String
    let kind: TransactionKind
}

struct CategorySuggestionsRequest: Encodable {
    let description: String
    let kind: TransactionKind
}

struct CategorySuggestion: Decodable, Hashable {
    let categoryId: UUID
    let score: Double
    let source: String
}

struct CategorySuggestionsResponse: Decodable {
    let suggestions: [CategorySuggestion]
}
