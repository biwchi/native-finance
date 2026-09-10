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
