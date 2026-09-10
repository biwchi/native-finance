import SwiftUI

struct FinanceMonthPickerButton: View {
    @Binding var month: Date
    @State private var isShowingPicker = false

    var body: some View {
        FinanceDatePickerButton(selection: monthSelection, isToolbarItem: true) {
            isShowingPicker = true
        }
        .popover(isPresented: $isShowingPicker) {
            DashboardMonthPicker(selection: $month, range: range)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var monthSelection: Binding<FinanceDateFilter> {
        Binding(
            get: { FinanceDateFilter(preset: .month, anchor: month, customEnd: month) },
            set: { month = BudgetMonth.start(of: $0.anchor) }
        )
    }

    private var range: ClosedRange<Date> {
        let current = BudgetMonth.start(of: .now)
        let first = Calendar.current.date(byAdding: .year, value: -1, to: min(current, month)) ?? month
        let last = Calendar.current.date(byAdding: .year, value: 1, to: max(current, month)) ?? month
        return first...last
    }
}
