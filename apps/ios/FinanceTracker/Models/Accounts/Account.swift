import Foundation

struct Account: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: AccountType
    let currency: String
    let icon: String
    let iconColor: AccountIconColor
    let createdAt: String
    let updatedAt: String
}
