import SwiftUI

extension View {
    func accountSelectorToolbar() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AccountSelector()
                }
            }
    }

    func leadingAccountSelectorToolbar() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountSelector(compact: true, isToolbarItem: true)
                }
            }
    }
}
