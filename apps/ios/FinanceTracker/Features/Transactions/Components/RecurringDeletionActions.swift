import SwiftUI

struct RecurringDeletionActions: View {
    let onAction: (RecurringDeletionAction) -> Void

    var body: some View {
        Button(RecurringDeletionAction.occurrence.title) { onAction(.occurrence) }
        Button(RecurringDeletionAction.stopRepeating.title) { onAction(.stopRepeating) }
        Button(RecurringDeletionAction.occurrenceAndFuture.title, role: .destructive) { onAction(.occurrenceAndFuture) }
        Button("Cancel", role: .cancel) {}
    }
}
