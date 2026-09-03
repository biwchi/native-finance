import Foundation

struct CreateCategoryRequest: Encodable {
    let name: String
    let kind: TransactionKind
    let parentId: UUID?
    let icon: String
    let color: CategoryColor
}
