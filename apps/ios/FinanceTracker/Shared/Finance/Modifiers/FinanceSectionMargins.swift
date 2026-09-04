import SwiftUI

struct FinanceSectionMargins: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.listSectionMargins(.vertical, 0) }
        else { content }
    }
}

struct FinanceListBottomSpacer: View {
    var body: some View {
        Section {
            Color.clear
                .frame(height: AppSpacing.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .modifier(FinanceSectionMargins())
    }
}
