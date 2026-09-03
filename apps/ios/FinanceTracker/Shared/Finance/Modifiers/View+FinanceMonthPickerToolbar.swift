import SwiftUI

extension View {
    func financeMonthPickerToolbar(month: Binding<Date>) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FinanceMonthPickerButton(month: month)
            }
        }
    }
}
