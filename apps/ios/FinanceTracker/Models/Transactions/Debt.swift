import Foundation

struct Debt: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    var icon: String? = nil
    var color: CategoryColor? = nil
}

