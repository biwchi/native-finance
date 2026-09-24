import SwiftUI

struct ScanDraftActions: View {
    @EnvironmentObject private var store: ScanDraftStore
    let item: ScanDraftItem
    let onReview: (UUID) -> Void
    let onReplace: (UUID) -> Void
    let onManualEntry: (UUID) -> Void
    let onDiscard: (UUID) -> Void

    var body: some View {
        AppRowActions(actions: actions)
    }

    private var actions: [AppRowActions.Action] {
        switch item.state {
        case .preparing, .queued, .running:
            return [.init(title: "Cancel", icon: "xmark", role: .destructive) { store.cancel(item.id) }]
        case .ready:
            return [
                .init(title: "Review", icon: "view") { onReview(item.id) },
                .init(title: "Dismiss", icon: "xmark", role: .destructive) { onDiscard(item.id) },
            ]
        case .failed, .interrupted:
            let retry = AppRowActions.Action(title: "Retry", icon: "refresh") { store.retry(item.id) }
            let replace = AppRowActions.Action(
                title: item.source.kind == .document ? "Replace file" : "Retake or replace",
                icon: item.source.kind == .document ? "page-plus" : "camera"
            ) { onReplace(item.id) }
            let retryFirst = item.failure?.code == .connection || item.state == .interrupted
            return (retryFirst ? [retry, replace] : [replace, retry]) + [
                .init(title: "Enter manually", icon: "edit-pencil") { onManualEntry(item.id) },
                .init(title: "Remove", icon: "trash", role: .destructive) { store.remove(item.id) },
            ]
        }
    }
}
