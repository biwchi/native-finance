import SwiftUI

struct FinanceMonthPickerButton: View {
    @Binding var month: Date
    @State private var isShowingPicker = false

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 32)
        }
        .accessibilityLabel("Choose month")
        .accessibilityValue(month.formatted(.dateTime.month(.wide).year()))
        .popover(isPresented: $isShowingPicker) {
            DashboardMonthPicker(selection: $month, range: range)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var range: ClosedRange<Date> {
        let current = BudgetMonth.start(of: .now)
        let first = Calendar.current.date(byAdding: .month, value: -12, to: current) ?? current
        let last = Calendar.current.date(byAdding: .month, value: 2, to: current) ?? current
        return first...last
    }
}
