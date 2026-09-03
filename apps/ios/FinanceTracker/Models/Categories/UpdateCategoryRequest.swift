import Foundation

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
