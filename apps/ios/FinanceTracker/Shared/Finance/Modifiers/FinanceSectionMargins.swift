import SwiftUI

struct FinanceSectionMargins: ViewModifier {
    var top: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .listSectionMargins(.top, top)
                .listSectionMargins(.bottom, 0)
        }
        else { content }
    }
}

struct FinanceListBottomSpacer: View {
    var height: CGFloat = AppSpacing.large

    var body: some View {
        Section {
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
