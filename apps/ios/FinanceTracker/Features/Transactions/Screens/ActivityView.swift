import SwiftUI

struct ActivityView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            TransactionListView(
                showsOverview: true,
                searchText: $searchText
            )
        }
    }
}
