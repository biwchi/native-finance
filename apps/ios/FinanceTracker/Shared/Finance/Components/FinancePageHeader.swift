import SwiftUI

struct FinancePageHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, AppSpacing.small)
            .listRowInsets(EdgeInsets(top: AppSpacing.extraSmall, leading: 0, bottom: AppSpacing.small, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
