import Foundation

struct SavingsGoal: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var accountId: UUID
    var targetAmount: String
    var icon: String
    var color: CategoryColor
    /// A calendar day, independent of the device's time zone.
    var deadline: String?
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    var target: Decimal { Decimal(string: targetAmount, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
}
