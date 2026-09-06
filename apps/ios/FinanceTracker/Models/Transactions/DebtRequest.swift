import Foundation

struct DebtRequest: Encodable {
    let name: String
    var icon: String = "user"
    var color: CategoryColor = .blue
}
