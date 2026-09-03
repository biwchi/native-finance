import SwiftUI

struct QuickKeyBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            AppColor.controlFill,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}
