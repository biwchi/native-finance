import Foundation

struct CategorySuggestionsRequest: Encodable {
    let description: String
    let kind: TransactionKind
}
