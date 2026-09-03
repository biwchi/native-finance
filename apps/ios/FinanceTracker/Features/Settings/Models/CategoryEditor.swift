import SwiftUI

struct CategoryEditor: Identifiable {
    let category: TransactionCategory?
    let kind: TransactionKind

    var id: String {
        category?.id.uuidString ?? "new-\(kind.rawValue)"
    }
}
