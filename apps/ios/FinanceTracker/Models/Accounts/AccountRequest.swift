import Foundation

struct AccountRequest: Encodable {
    let name: String
    let type: AccountType
    let currency: String
    let icon: String
    let iconColor: AccountIconColor
}
