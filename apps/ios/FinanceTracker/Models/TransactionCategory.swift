import Foundation

enum CategoryColor: String, Codable, CaseIterable, Identifiable {
    case red
    case coral
    case orange
    case amber
    case yellow
    case lime
    case green
    case mint
    case teal
    case turquoise
    case cyan
    case sky
    case blue
    case navy
    case indigo
    case violet
    case purple
    case lavender
    case pink
    case rose
    case brown
    case slate
    case gray

    var id: Self { self }

    var title: String { rawValue.capitalized }
}

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

struct CreateCategoryRequest: Encodable {
    let name: String
    let kind: TransactionKind
    let parentId: UUID?
    let icon: String
    let color: CategoryColor
}

struct UpdateCategoryRequest: Encodable {
    let name: String
    let parentId: UUID?
    let icon: String
    let color: CategoryColor

    private enum CodingKeys: String, CodingKey {
        case name
        case parentId
        case icon
        case color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(parentId, forKey: .parentId)
        try container.encode(icon, forKey: .icon)
        try container.encode(color, forKey: .color)
    }
}

struct DeleteCategoryResponse: Decodable {
    let id: UUID
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
