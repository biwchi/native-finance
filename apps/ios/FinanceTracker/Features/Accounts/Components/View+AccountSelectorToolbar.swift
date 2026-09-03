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
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        AccountSelector(compact: true).padding(.leading, -12)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { AccountSelector(compact: true) }
                }
            }
    }
}
