import SwiftUI

struct FinanceSectionMargins: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.listSectionMargins(.vertical, 0) }
        else { content }
    }
}
