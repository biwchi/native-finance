import SwiftUI

struct NewTransactionCategoryView: View {
    let kind: TransactionKind
    let onCreated: (TransactionCategory) -> Void

    var body: some View {
        CategoryEditorView(
            editor: CategoryEditor(category: nil, kind: kind),
            allowsKindChanges: false,
            onCreated: onCreated
        )
    }
}
