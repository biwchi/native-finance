import SwiftUI

struct FinanceMonthPickerButton: View {
    @Binding var month: Date
    @State private var isShowingPicker = false

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            HStack(spacing: AppSpacing.compact) {
                Text(month.formatted(.dateTime.month(.abbreviated).year()))
                AppIcon("nav-arrow-down", size: 11)
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 32)
            .fixedSize()
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
