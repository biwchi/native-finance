import Foundation

struct Debt: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    var icon: String? = nil
    var color: CategoryColor? = nil
    var sortOrder: Int? = nil

    static func orderedBefore(_ lhs: Debt, _ rhs: Debt) -> Bool {
        let leftOrder = lhs.sortOrder ?? 0
        let rightOrder = rhs.sortOrder ?? 0
        if leftOrder != rightOrder { return leftOrder < rightOrder }
        let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
