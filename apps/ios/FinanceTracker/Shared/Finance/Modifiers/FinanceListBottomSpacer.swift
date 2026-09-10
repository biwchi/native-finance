import SwiftUI

struct FinanceListBottomSpacer: View {
    var height: CGFloat = AppSpacing.large

    var body: some View {
        AppSection {
            Color.clear
                .frame(height: height)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .modifier(FinanceSectionMargins())
    }
}
