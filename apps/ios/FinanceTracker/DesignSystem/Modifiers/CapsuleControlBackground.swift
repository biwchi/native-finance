import SwiftUI

struct CapsuleControlBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppColor.controlFill, in: Capsule())
    }
}
