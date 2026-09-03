import Foundation

struct AccountOrderRequest: Encodable {
    let accountIds: [UUID]
}
