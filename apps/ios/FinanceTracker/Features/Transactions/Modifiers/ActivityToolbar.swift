import SwiftUI

struct ActivityToolbar: ViewModifier {
    let isEnabled: Bool
    @Binding var month: Date

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .leadingAccountSelectorToolbar()
                .financeMonthPickerToolbar(month: $month)
        }
        else { content }
    }
}
