import Foundation

struct AccountRequest: Encodable {
    let name: String
    let currency: String
    let icon: String
    let iconColor: AccountIconColor
    var initialBalance: String = "0"
}
