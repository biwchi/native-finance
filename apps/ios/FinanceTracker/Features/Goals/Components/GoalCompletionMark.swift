import SwiftUI

struct GoalCompletionMark: View {
    var body: some View {
        AppIcon("check", size: 16)
            .dynamicTypeSize(.large)
            .foregroundStyle(AppColor.foreground(on: AppColor.positive))
            .frame(width: 26, height: 26)
            .background(AppColor.positive, in: Circle())
            .accessibilityLabel("Goal completed")
    }
}
