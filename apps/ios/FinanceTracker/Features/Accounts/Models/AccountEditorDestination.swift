import SwiftUI

enum AccountEditorDestination: Identifiable {
    case add
    case edit(Account)

    var id: String {
        switch self {
        case .add: "add"
        case let .edit(account): account.id.uuidString
        }
    }

    var account: Account? {
        if case let .edit(account) = self {
            account
        } else {
            nil
        }
    }
}
