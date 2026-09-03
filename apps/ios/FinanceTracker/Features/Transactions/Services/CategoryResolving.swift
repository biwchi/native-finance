import Foundation

protocol CategoryResolving {
    func resolve(
        description: String,
        kind: TransactionKind,
        categories: [TransactionCategory]
    ) async -> CategoryResolution?
}
