import SwiftUI

struct RecurringAccountsToolbar: ViewModifier {
    let allAccounts: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if allAccounts { content }
        else { content.accountSelectorToolbar() }
    }
}
