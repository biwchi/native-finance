import SwiftUI

enum AccountManagementAlert: Identifiable {
    case confirmDeletion(Account)
    case error(String)

    var id: String {
        switch self {
        case let .confirmDeletion(account): "delete-\(account.id.uuidString)"
        case let .error(message): "error-\(message)"
        }
    }
}
