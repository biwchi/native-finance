import SwiftUI

struct ActivityView: View {
    var body: some View {
        NavigationStack {
            TransactionListView(showsOverview: true)
        }
    }
}
