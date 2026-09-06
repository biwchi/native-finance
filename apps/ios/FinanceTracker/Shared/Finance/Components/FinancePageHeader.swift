import SwiftUI

struct FinancePageHeader: View {
    var title: String? = nil
    var dateSelection: Binding<FinanceDateFilter>? = nil

    var body: some View {
        Group {
            if let dateSelection {
                FinanceDatePickerButton(selection: dateSelection)
            } else if let title {
                Text(title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, AppSpacing.small)
        .listRowInsets(EdgeInsets(top: AppSpacing.extraSmall, leading: 0, bottom: AppSpacing.small, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
