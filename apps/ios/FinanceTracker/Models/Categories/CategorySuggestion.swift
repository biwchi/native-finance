import Foundation

struct CategorySuggestion: Decodable, Hashable {
    let categoryId: UUID
    let score: Double
    let source: String
}
