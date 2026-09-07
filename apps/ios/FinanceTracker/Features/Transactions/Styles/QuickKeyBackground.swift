import SwiftUI

struct QuickKeyBackground: ViewModifier {
    let isUtility: Bool

    func body(content: Content) -> some View {
        content.background(
            isUtility ? AppColor.keypadUtilityFill : AppColor.controlFill,
            in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
        )
    }
}
