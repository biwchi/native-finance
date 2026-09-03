import Foundation

struct TransactionCategory: Codable, Identifiable, Hashable {
    let id: UUID
    let systemKey: String?
    let name: String
    let kind: TransactionKind
    let parentId: UUID?
    let icon: String?
    let color: CategoryColor?
    let isSystem: Bool
    let examples: [String]?
    let sortOrder: Int?
    let createdAt: Date?
    let updatedAt: Date?

    var classificationExamples: [String] {
        [name] + (examples ?? [])
    }

    init(
        id: UUID,
        systemKey: String?,
        name: String,
        kind: TransactionKind,
        parentId: UUID? = nil,
        icon: String? = nil,
        color: CategoryColor? = nil,
        isSystem: Bool,
        examples: [String]?,
        sortOrder: Int?,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.systemKey = systemKey
        self.name = name
        self.kind = kind
        self.parentId = parentId
        self.icon = icon
        self.color = color
        self.isSystem = isSystem
        self.examples = examples
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
